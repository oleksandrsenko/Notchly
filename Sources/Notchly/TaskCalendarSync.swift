import AppKit
import Combine
import EventKit

/// Зеркалит задачи в отдельный календарь «Notchly» (в iCloud, если он подключён) — так они видны
/// и на iPhone. Работает в обе стороны: задача, перенесённая или удалённая на телефоне, меняется и здесь.
///
/// Задача и событие связаны ссылкой `notchly://task/<id>` в поле URL события — она переживает
/// синхронизацию iCloud, в отличие от идентификаторов EventKit. Чтобы понять, какая сторона изменилась,
/// храним состояние пары на момент последней синхронизации.
final class TaskCalendarSync {
    /// Что сравниваем у задачи и события.
    private struct State: Codable, Equatable {
        var title: String
        var day: String
        var time: String?
    }

    static let calendarTitle = "Notchly"
    private static let scheme = "notchly"
    /// Задачи со временем становятся часовыми событиями.
    private static let duration: TimeInterval = 3600

    private let tasks: TasksStore
    private let calendar: CalendarService
    private let settings: AppSettings
    private var store: EKEventStore { calendar.store }
    private var synced: [UUID: State]
    private var bag = Set<AnyCancellable>()
    private var pending: DispatchWorkItem?
    /// Пока применяем изменения с телефона к задачам, их собственное эхо не запускает новый проход.
    private var applying = false
    private let stateKey = "calendarSync.state"
    private static let calendarIDKey = "calendarSync.calendarID"
    private var calendarKey: String { Self.calendarIDKey }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(tasks: TasksStore, calendar: CalendarService, settings: AppSettings) {
        self.tasks = tasks
        self.calendar = calendar
        self.settings = settings
        let data = UserDefaults.standard.data(forKey: stateKey)
        synced = data.flatMap { try? JSONDecoder().decode([UUID: State].self, from: $0) } ?? [:]
    }

    func start() {
        // Свои задачи изменились, календарь перечитан (в т. ч. правки с телефона) или включили синхронизацию.
        tasks.$items.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &bag)
        calendar.$revision.sink { [weak self] _ in self?.schedule() }.store(in: &bag)
        settings.$calendarSync.removeDuplicates().sink { [weak self] on in
            if on { self?.calendar.requestIfNeeded() }
            self?.schedule()
        }.store(in: &bag)
    }

    private func schedule() {
        guard !applying else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Сверка

    private func reconcile() {
        guard settings.calendarSync, calendar.isConnected,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let target = notchlyCalendar() else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Прошлое не трогаем: выполненные давно задачи и старые события живут сами по себе.
        guard let from = cal.date(byAdding: .day, value: -1, to: today),
              let to = cal.date(byAdding: .year, value: 1, to: today) else { return }

        var events: [UUID: EKEvent] = [:]
        var foreign: [EKEvent] = []
        var changed = false
        for event in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [target])) {
            if let id = Self.taskID(of: event) {
                // Дубль одной задачи (например, iCloud догрузил старую копию) — лишний убираем.
                if events[id] != nil { remove(event); changed = true } else { events[id] = event }
            } else if !event.hasRecurrenceRules {
                foreign.append(event)
            }
        }
        let inRange = { (day: Date) in day >= from && day < to }
        // Календарь пуст, хотя раньше в нём были наши события, — скорее всего iCloud ещё не подгрузился,
        // учётная запись отключена или календарь очистили. Задачи не удаляем, а выкладываем заново.
        let expected = tasks.items.filter { !$0.done && synced[$0.id] != nil && inRange(TasksStore.day(of: $0)) }
        if events.isEmpty && expected.count >= 2 {
            for task in expected { synced[task.id] = nil }
        }
        var taskEdits: [(UUID, State?)] = []   // nil — удалить задачу
        var newTasks: [(State, EKEvent)] = []

        for task in tasks.items {
            let day = TasksStore.day(of: task)
            let mine = state(of: task)
            let event = events.removeValue(forKey: task.id)
            let last = synced[task.id]
            // Выполненные задачи и задачи вне окна в календаре не нужны.
            guard !task.done, inRange(day) else {
                if let event { remove(event); changed = true }
                synced[task.id] = nil
                continue
            }
            guard let event else {
                if last != nil {
                    // Было в календаре, а теперь нет — удалили на телефоне.
                    taskEdits.append((task.id, nil))
                    synced[task.id] = nil
                } else {
                    write(task, into: EKEvent(eventStore: store), calendar: target, isNew: true)
                    synced[task.id] = mine
                    changed = true
                }
                continue
            }
            let theirs = state(of: event)
            if theirs == mine {
                synced[task.id] = mine
            } else if mine == last {
                // Поменяли на телефоне.
                taskEdits.append((task.id, theirs))
                synced[task.id] = theirs
            } else {
                // Поменяли здесь (или с обеих сторон — тогда побеждает Mac).
                write(task, into: event, calendar: target, isNew: false)
                synced[task.id] = mine
                changed = true
            }
        }
        // События, оставшиеся без задачи.
        for (id, event) in events {
            if synced[id] != nil {
                // Задачу удалили здесь.
                remove(event)
                synced[id] = nil
                changed = true
            } else if tasks.items.contains(where: { $0.id == id }) == false {
                newTasks.append((state(of: event), event))
            }
        }
        // Событие, добавленное в календарь «Notchly» на телефоне, становится задачей.
        for event in foreign { newTasks.append((state(of: event), event)) }

        if changed {
            do { try store.commit() } catch { NSLog("Calendar sync: \(error)") }
        }
        if !taskEdits.isEmpty || !newTasks.isEmpty {
            applying = true
            for (id, state) in taskEdits {
                if let state { tasks.applySynced(id, text: state.title, day: Self.date(state.day), time: state.time) } else { tasks.remove(id) }
            }
            var linked = false
            for (state, event) in newTasks {
                guard let day = Self.date(state.day) else { continue }
                let id = tasks.addSynced(state.title, day: day, time: state.time, notes: event.notes)
                event.url = Self.url(for: id)
                try? store.save(event, span: .thisEvent, commit: false)
                synced[id] = state
                linked = true
            }
            if linked { try? store.commit() }
            applying = false
        }
        persist()
    }

    // MARK: - Событие ⇄ задача

    private func state(of task: TaskItem) -> State {
        State(title: task.text, day: Self.dayFormat.string(from: TasksStore.day(of: task)), time: task.time)
    }

    private func state(of event: EKEvent) -> State {
        let time = event.isAllDay ? nil
            : event.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ru_RU")))
        return State(title: event.title ?? "", day: Self.dayFormat.string(from: event.startDate), time: time)
    }

    private func write(_ task: TaskItem, into event: EKEvent, calendar target: EKCalendar, isNew: Bool) {
        let cal = Calendar.current
        let day = TasksStore.day(of: task)
        event.calendar = target
        event.title = task.text
        event.notes = task.notes
        event.url = Self.url(for: task.id)
        let parts = task.time?.split(separator: ":").compactMap { Int($0) } ?? []
        if parts.count == 2, let start = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) {
            // Длительность, выставленную на телефоне, сохраняем.
            let length = (!isNew && !event.isAllDay) ? max(event.endDate.timeIntervalSince(event.startDate), 900) : Self.duration
            event.isAllDay = false
            event.startDate = start
            event.endDate = start.addingTimeInterval(length)
            if isNew { event.alarms = [EKAlarm(relativeOffset: -10 * 60)] }
        } else {
            event.isAllDay = true
            event.startDate = day
            event.endDate = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        do { try store.save(event, span: .thisEvent, commit: false) } catch { NSLog("Calendar sync save: \(error)") }
    }

    private func remove(_ event: EKEvent) {
        do { try store.remove(event, span: .thisEvent, commit: false) } catch { NSLog("Calendar sync remove: \(error)") }
    }

    /// Событие — копия задачи (сама задача и так видна и напоминает о себе).
    static func isMirror(_ event: EKEvent) -> Bool {
        if event.url?.scheme == scheme { return true }
        guard let id = UserDefaults.standard.string(forKey: calendarIDKey) else { return false }
        return event.calendar?.calendarIdentifier == id
    }

    private static func url(for id: UUID) -> URL? { URL(string: "\(scheme)://task/\(id.uuidString)") }

    private static func taskID(of event: EKEvent) -> UUID? {
        guard let url = event.url, url.scheme == scheme else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    private static func date(_ day: String) -> Date? { dayFormat.date(from: day).map { Calendar.current.startOfDay(for: $0) } }

    // MARK: - Календарь «Notchly»

    /// Свой календарь: в iCloud, чтобы он был на iPhone; без iCloud — там же, где календарь по умолчанию.
    private func notchlyCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let found = store.calendar(withIdentifier: id) {
            return found
        }
        if let found = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(found.calendarIdentifier, forKey: calendarKey)
            return found
        }
        let sources = store.sources
        let source = sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        guard let source else { return nil }
        let created = EKCalendar(for: .event, eventStore: store)
        created.title = Self.calendarTitle
        created.source = source
        created.cgColor = NSColor.systemPurple.cgColor
        do {
            try store.saveCalendar(created, commit: true)
            UserDefaults.standard.set(created.calendarIdentifier, forKey: calendarKey)
            // Новый календарь — всё, что было «синхронизировано» раньше, пишем заново.
            synced = [:]
            return created
        } catch {
            NSLog("Calendar sync: cannot create calendar: \(error)")
            return nil
        }
    }

    /// Какой учётной записи принадлежит календарь — для подписи в настройках.
    var accountTitle: String? {
        guard let id = UserDefaults.standard.string(forKey: calendarKey) else { return nil }
        return store.calendar(withIdentifier: id)?.source.title
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(synced) { UserDefaults.standard.set(data, forKey: stateKey) }
    }
}
