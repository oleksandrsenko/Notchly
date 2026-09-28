import SwiftUI

/// «Календарь» рядом с задачами: месяц слева, выбранный день справа — задачи и события macOS-календаря,
/// чтобы видеть, когда свободно, и планировать наперёд с повтором на несколько недель.
struct CalendarView: View {
    @ObservedObject var store: TasksStore
    var calendar: CalendarService
    var focus: FocusTimer

    /// Без доступа к календарю (снапшоты) — пустой сервис: событий нет, только задачи.
    static let offline = CalendarService()

    var body: some View {
        HStack(spacing: 12) {
            MonthGrid(store: store, calendar: calendar)
                .frame(width: 232)
            DayAgenda(store: store, calendar: calendar, focus: focus)
        }
        .onAppear { calendar.requestIfNeeded() }
    }
}

// MARK: - Шапка: месяц и стрелки

/// В шапке вкладки: «‹ Октябрь 2026 ›» и «Сегодня».
struct MonthHeader: View {
    @ObservedObject var store: TasksStore

    private var title: String {
        let f = DateFormatter()
        f.locale = Loc.locale
        f.dateFormat = "LLLL yyyy"
        let text = f.string(from: store.calendarMonth)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func shift(_ months: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: months, to: store.calendarMonth) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { store.calendarMonth = month }
    }

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left") { shift(-1) }
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .contentTransition(.numericText())
                .frame(minWidth: 104)
            arrow("chevron.right") { shift(1) }
            let today = TasksStore.date(forOffset: 0)
            if store.calendarDay != today || store.calendarMonth != TasksStore.startOfMonth(today) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        store.calendarDay = today
                        store.calendarMonth = TasksStore.startOfMonth(today)
                    }
                } label: {
                    Text(L("Сегодня"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.06)))
        .fixedSize()
    }

    private func arrow(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Месяц

private struct MonthGrid: View {
    @ObservedObject var store: TasksStore
    @ObservedObject var calendar: CalendarService
    @Namespace private var ns

    private var cal: Calendar { Calendar.current }

    /// Недели месяца (обычно 5), начиная с первого дня недели, в которую попало 1-е число.
    private var cells: [Date] {
        let first = store.calendarMonth
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let length = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weeks = Int((Double(lead + length) / 7).rounded(.up))
        guard let start = cal.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Loc.locale
        let symbols = (f.shortStandaloneWeekdaySymbols ?? []).map { String($0.prefix(2)) }
        guard symbols.count == 7 else { return [] }
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        let days = cells
        let events = eventDays(days)
        let today = TasksStore.date(forOffset: 0)
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { i, symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(i >= 5 ? 0.3 : 0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day,
                            inMonth: cal.isDate(day, equalTo: store.calendarMonth, toGranularity: .month),
                            isToday: day == today, isPast: day < today,
                            selected: day == store.calendarDay,
                            openTasks: store.items.contains { !$0.done && TasksStore.day(of: $0) == day },
                            hasEvents: events.contains(day), ns: ns) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.calendarDay = day
                            if !cal.isDate(day, equalTo: store.calendarMonth, toGranularity: .month) {
                                store.calendarMonth = TasksStore.startOfMonth(day)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        // Свайп по сетке листает месяцы.
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            let step = value.translation.width < 0 ? 1 : -1
            if let month = cal.date(byAdding: .month, value: step, to: store.calendarMonth) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { store.calendarMonth = month }
            }
        })
    }

    /// Дни с событиями календаря — одним запросом на всю сетку.
    private func eventDays(_ days: [Date]) -> Set<Date> {
        guard calendar.isConnected, let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return [] }
        _ = calendar.revision
        var result = Set<Date>()
        for event in calendar.events(from: first, to: end) {
            var day = cal.startOfDay(for: event.start)
            // Многодневные события отмечаем на каждом дне.
            while day < event.end && day < end {
                result.insert(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            result.insert(cal.startOfDay(for: event.start))
        }
        return result
    }
}

private struct DayCell: View {
    var day: Date
    var inMonth: Bool
    var isToday: Bool
    var isPast: Bool
    var selected: Bool
    var openTasks: Bool
    var hasEvents: Bool
    var ns: Namespace.ID
    var onTap: () -> Void
    @ViewState private var hovering = false

    private var number: String { "\(Calendar.current.component(.day, from: day))" }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if selected {
                    Circle().fill(isToday ? Color.accentColor : .white)
                        .matchedGeometryEffect(id: "day", in: ns)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else if hovering {
                    Circle().fill(.white.opacity(0.1))
                }
                Text(number)
                    .font(.system(size: 10, weight: isToday || selected ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                // Точки: белая — задачи, голубая — события календаря.
                HStack(spacing: 2) {
                    if openTasks { Circle().fill(dotColor(.white)).frame(width: 3, height: 3) }
                    if hasEvents { Circle().fill(dotColor(Color(red: 0.4, green: 0.7, blue: 1))).frame(width: 3, height: 3) }
                }
                .offset(y: 6.5)
            }
            .frame(width: 17, height: 17)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }

    private var foreground: Color {
        if selected { return isToday ? .white : .black }
        if !inMonth { return .white.opacity(0.2) }
        return .white.opacity(isPast ? 0.4 : 0.85)
    }

    private func dotColor(_ color: Color) -> Color {
        selected ? (isToday ? Color.white : Color.black).opacity(0.7) : color.opacity(inMonth ? 0.8 : 0.3)
    }
}

// MARK: - День

private struct DayAgenda: View {
    @ObservedObject var store: TasksStore
    @ObservedObject var calendar: CalendarService
    var focus: FocusTimer
    @ViewState private var draft = ""
    @ViewState private var weeks = 1
    @ViewState private var added: String?
    @FocusState private var draftFocused: Bool

    private var day: Date { store.calendarDay }

    private var title: String {
        let today = TasksStore.date(forOffset: 0)
        let offset = Calendar.current.dateComponents([.day], from: today, to: day).day ?? 0
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Loc.locale))
        let text = date.prefix(1).uppercased() + date.dropFirst()
        switch offset {
        case 0: return L("Сегодня") + " · " + text
        case 1: return L("Завтра") + " · " + text
        default: return text
        }
    }

    private var events: [CalendarService.Event] {
        _ = calendar.revision
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return [] }
        return calendar.events(from: day, to: end)
    }

    var body: some View {
        let tasks = store.tasks(on: day)
        let events = events
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(busySummary(tasks: tasks, events: events))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(height: 16)

            if tasks.isEmpty && events.isEmpty {
                VStack(spacing: 3) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(L("День свободен — можно планировать"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(events) { EventRow(event: $0) }
                        ForEach(tasks) { task in
                            AgendaTaskRow(task: task, overdue: TasksStore.day(of: task) < day) {
                                store.toggle(task.id)
                            } onDelete: { store.remove(task.id) }
                              onDeleteSeries: { store.removeSeries(from: task.id) }
                              onFocus: { focus.start(taskID: task.id, title: task.text) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            addRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: day)
    }

    /// «Занято 10:00–11:30, 18:00» — чтобы сразу видеть свободные окна.
    private func busySummary(tasks: [TaskItem], events: [CalendarService.Event]) -> String {
        if let added { return added }
        let hm = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Loc.locale)
        var slots = events.filter { !$0.isAllDay }.map { ($0.start.formatted(hm), $0.start.formatted(hm) + "–" + $0.end.formatted(hm)) }
        slots += tasks.filter { !$0.done }.compactMap { t in t.time.map { ($0, $0) } }
        guard !slots.isEmpty else {
            return events.contains(where: \.isAllDay) ? L("Событие на весь день") : ""
        }
        let sorted = slots.sorted { $0.0 < $1.0 }.map(\.1)
        return L("Занято: %@", sorted.prefix(3).joined(separator: ", ") + (sorted.count > 3 ? " …" : ""))
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(draftFocused ? 0.8 : 0.35))
            TextField(L("Задача — «немецкий 18:30»"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($draftFocused)
                .onSubmit(submit)
            RepeatMenu(weeks: $weeks)
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(draftFocused ? 0.09 : 0.06)))
        .animation(.easeOut(duration: 0.2), value: draftFocused)
    }

    private func submit() {
        let days = store.addParsed(draft, fallbackDay: day, weeks: weeks)
        draft = ""
        draftFocused = true
        guard !days.isEmpty else { return }
        // Задача легла на другие дни — подскажем куда.
        if days.count > 1 || days.first != day {
            withAnimation(.easeOut(duration: 0.2)) {
                added = Loc.plural(days.count, "добавлена", "добавлено", "добавлено", en: "added", enPlural: "added")
                    + " \(days.count) · " + TasksView.daysSummary(days)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(.easeOut(duration: 0.3)) { added = nil } }
        }
        weeks = 1
    }
}

/// Меню повтора: один раз или каждую неделю на 2–12 недель вперёд.
private struct RepeatMenu: View {
    @Binding var weeks: Int
    static let options = [1, 2, 3, 4, 8, 12]

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.self) { n in
                Button {
                    weeks = n
                } label: {
                    if n == weeks { Label(Self.title(n), systemImage: "checkmark") } else { Text(Self.title(n)) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                    .font(.system(size: 9.5, weight: .bold))
                if weeks > 1 {
                    Text(L("%@ нед.", "\(weeks)"))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(weeks > 1 ? .black : .white.opacity(0.6))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(weeks > 1 ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08))))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Повторять каждую неделю"))
    }

    static func title(_ n: Int) -> String {
        switch n {
        case 1: return L("Не повторять")
        case 4: return L("Каждую неделю — месяц")
        case 12: return L("Каждую неделю — 3 месяца")
        default: return L("Каждую неделю — %@", "\(n) " + Loc.plural(n, "неделя", "недели", "недель", en: "week", enPlural: "weeks"))
        }
    }
}

private struct EventRow: View {
    var event: CalendarService.Event

    var body: some View {
        let hm = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Loc.locale)
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color ?? .systemBlue))
                .frame(width: 3, height: 14)
            Text(event.title)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let link = event.link {
                Button { NSWorkspace.shared.open(link) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(PressableStyle())
                .help(link.absoluteString)
            }
            Text(event.isAllDay ? L("весь день") : event.start.formatted(hm) + "–" + event.end.formatted(hm))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .help(L("Событие календаря"))
    }
}

private struct AgendaTaskRow: View {
    var task: TaskItem
    var overdue: Bool
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onDeleteSeries: () -> Void
    var onFocus: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                ZStack {
                    Circle().strokeBorder(.white.opacity(task.done ? 0 : 0.45), lineWidth: 1.5)
                    if task.done {
                        Circle().fill(Color.green)
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            Text(task.text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(task.done ? 0.35 : 0.9))
                .strikethrough(task.done, color: .white.opacity(0.35))
                .lineLimit(1)
            if task.seriesID != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .help(L("Повторяющаяся задача"))
            }
            if overdue {
                Text(L("перенесена"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.8))
            }
            Spacer(minLength: 4)
            if hovering && !task.done {
                Button(action: onFocus) {
                    Image(systemName: "timer")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(L("Фокус 25 минут над этой задачей"))
            }
            ZStack(alignment: .trailing) {
                if let time = task.time {
                    Text(time)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(task.done ? 0.3 : 0.7))
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .opacity(hovering ? 0 : 1)
                }
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Удалить задачу"))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .contextMenu {
            Button(task.done ? L("Вернуть в работу") : L("Выполнено"), action: onToggle)
            Button(L("Удалить"), role: .destructive, action: onDelete)
            if task.seriesID != nil {
                Button(L("Удалить этот и следующие повторы"), role: .destructive, action: onDeleteSeries)
            }
        }
    }
}
