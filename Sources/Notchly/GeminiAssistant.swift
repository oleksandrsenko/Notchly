import Foundation

/// Небольшой помощник на Gemini API: превращает фразу вроде «сегодня в 5 спортзал, в 10 созвон»
/// в задачи и коротко отвечает на вопросы. Ключ API хранится в Связке ключей.
final class GeminiAssistant: ObservableObject {
    struct SuggestedTask {
        var text: String
        var time: String?
        /// Дни задачи; пусто — день, открытый в планере.
        var days: [Date] = []
        /// Повтор на столько недель подряд (1 — без повтора).
        var weeks = 1
    }

    /// Правка существующей задачи: «удали бег в субботу», «перенеси немецкий на 19:30».
    struct TaskChange {
        enum Action: String { case delete, deleteSeries, update, done }
        var id: UUID
        var action: Action
        var text: String?
        var time: String?
        /// Убрать время («на весь день»).
        var clearTime = false
        var day: Date?
    }

    @Published private(set) var hasKey = false
    @Published private(set) var isThinking = false
    @Published private(set) var reply: String?
    @Published private(set) var error: String?

    private static let service = "gemini"
    private static let account = "api-key"
    /// Если модель перегружена (503), упёрлась в лимит (429) или снята (404) — пробуем следующую.
    /// Последняя сработавшая модель запоминается и пробуется первой.
    private static let baseModels = ["gemini-3.8-flash", "gemini-flash-latest", "gemini-3.5-flash-lite",
                                     "gemini-flash-lite-latest"]
    private static var models: [String] {
        let last = UserDefaults.standard.string(forKey: "gemini.lastModel")
        return (last.map { [$0] } ?? []) + baseModels.filter { $0 != last }
    }

    init() {
        hasKey = Keychain.contains(service: Self.service, account: Self.account)
    }

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasKey = Keychain.set(Data(trimmed.utf8), service: Self.service, account: Self.account)
        error = hasKey ? nil : L("Не удалось сохранить ключ в Связке ключей")
    }

    func removeKey() {
        Keychain.delete(service: Self.service, account: Self.account)
        hasKey = false
        reply = nil
    }

    func dismissReply() {
        reply = nil
        error = nil
    }

    func ask(_ prompt: String, tasks: [TaskItem], events: [CalendarService.Event] = [], selectedDay: Date = Date(),
             completion: @escaping ([SuggestedTask], [TaskChange]) -> Void) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking,
              let keyData = Keychain.data(service: Self.service, account: Self.account),
              let key = String(data: keyData, encoding: .utf8) else { return }
        isThinking = true
        error = nil
        reply = nil
        let refs = Self.references(tasks)
        let body = Self.requestBody(for: text, tasks: refs, events: events, selectedDay: selectedDay)
        send(body: body, key: key, models: Self.models) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isThinking = false
                switch result {
                case .success(let answer):
                    self.reply = answer.reply.isEmpty ? nil : answer.reply
                    let ids = Dictionary(uniqueKeysWithValues: refs.map { ($0.ref, $0.task.id) })
                    let changes = answer.changes.compactMap { raw -> TaskChange? in
                        guard let id = ids[raw.ref], let action = TaskChange.Action(rawValue: raw.action) else { return nil }
                        return TaskChange(id: id, action: action, text: raw.text?.isEmpty == false ? raw.text : nil,
                                          time: raw.time, clearTime: raw.clearTime, day: raw.day)
                    }
                    completion(answer.tasks, changes)
                case .failure(let message):
                    self.error = message
                }
            }
        }
    }

    /// Проверка без интерфейса: настоящий запрос приложения (со схемой ответа) по цепочке моделей.
    static func selfTest(_ done: @escaping (String) -> Void) {
        guard let keyData = Keychain.data(service: service, account: account),
              let key = String(data: keyData, encoding: .utf8) else { return done("ключ не найден в Связке ключей") }
        let assistant = GeminiAssistant()
        assistant.send(body: requestBody(for: "сегодня в 5 спортзал; в четверг, пятницу и субботу бег в 7 утра; немецкий каждый вторник в 19 на 3 недели", tasks: []), key: key, models: models) { result in
            withExtendedLifetime(assistant) {}
            switch result {
            case .success(let answer):
                let model = UserDefaults.standard.string(forKey: "gemini.lastModel") ?? "?"
                done("OK (\(model)): задач \(answer.tasks.count) — " + answer.tasks.map {
                    "\($0.days.map { isoDay.string(from: $0) }.joined(separator: "/")) \($0.time ?? "--") ×\($0.weeks) \($0.text)"
                }.joined(separator: ", "))
            case .failure(let message):
                done("ошибка: \(message)")
            }
        }
    }

    // MARK: - Запрос

    private struct RawChange { var ref: String; var action: String; var text: String?; var time: String?; var clearTime: Bool; var day: Date? }
    private struct Answer { var reply: String; var tasks: [SuggestedTask]; var changes: [RawChange] = [] }

    /// Невыполненные задачи на два месяца вперёд с короткими метками t1, t2… — по ним модель ссылается на задачу.
    private static func references(_ tasks: [TaskItem]) -> [(ref: String, task: TaskItem)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let horizon = cal.date(byAdding: .day, value: 60, to: today) ?? today
        return tasks.filter { !$0.done && TasksStore.day(of: $0) < horizon }
            .sorted { (TasksStore.day(of: $0), $0.time ?? "") < (TasksStore.day(of: $1), $1.time ?? "") }
            .prefix(120)
            .enumerated().map { ("t\($0.offset + 1)", $0.element) }
    }
    private enum Result { case success(Answer), failure(String) }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func requestBody(for text: String, tasks: [(ref: String, task: TaskItem)], events: [CalendarService.Event] = [],
                                    selectedDay: Date = Date()) -> [String: Any] {
        let ru = Locale(identifier: "ru_RU")
        let now = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(ru))
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Модели трудно самой считать даты — даём готовую таблицу на три недели вперёд.
        let upcoming = (0..<21).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .map { "\(isoDay.string(from: $0)) — " + $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ru)) }
            .joined(separator: "\n")
        let current = tasks.map { ref, task in
            "- [\(ref)] " + isoDay.string(from: max(TasksStore.day(of: task), today)) + " " + (task.time.map { "\($0) " } ?? "")
                + task.text + (task.seriesID != nil ? " (повторяется)" : "")
        }.joined(separator: "\n")
        let busy = events.map { e in
            "- " + isoDay.string(from: e.start) + " "
                + (e.isAllDay ? "весь день" : e.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ru))
                   + "–" + e.end.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ru)))
                + " " + e.title
        }.joined(separator: "\n")
        let system = """
        Ты — компактный помощник в Notchly — «острове» в вырезе экрана Mac. Сейчас \(now).
        Даты ближайших дней:
        \(upcoming)

        Задачи пользователя ([метка] дата, время, текст):
        \(current.isEmpty ? "(нет)" : current)
        События календаря:
        \(busy.isEmpty ? "(нет)" : busy)
        В планере сейчас открыт день \(isoDay.string(from: selectedDay)).

        Если пользователь описывает планы или дела — разбей их на короткие задачи (до 60 символов,
        начинаются с глагола или существительного, без времени и дат в тексте). Время укажи отдельно в формате ЧЧ:ММ
        в 24-часовом формате; «в 5» днём/вечером — это 17:00, «в 10» утром — 10:00, если из контекста не ясно иное.
        Дни задачи укажи в dates датами ГГГГ-ММ-ДД из таблицы выше: «в четверг» — ближайший четверг,
        «в чт, пт и сб» — три даты у одной задачи, «завтра» — завтрашняя дата. Разные дела на разные дни —
        разные задачи со своими датами. Если день не назван — dates пустой (задача попадёт в открытый день).
        Если дело повторяется («каждый вторник», «на 3 недели вперёд», «по средам месяц») — в dates первая дата(ы),
        а в weeks — сколько недель подряд повторять (месяц — 4); без повтора weeks = 1.
        Если пользователь просит изменить уже существующие задачи — верни их в changes по меткам из списка:
        «удали / отмени» — action delete; «удали все повторы / больше не хожу» у повторяющейся — deleteSeries
        (удалит эту и все следующие); «сделал / выполнил» — done; «перенеси / поменяй время / переименуй» — update,
        и заполни только то, что меняется: date (ГГГГ-ММ-ДД), time (ЧЧ:ММ, или «-», чтобы убрать время), text.
        «Удали планы на субботу» — delete для каждой задачи этой даты. Перенос не создаёт новую задачу.
        События календаря менять нельзя — только задачи. Коротко скажи в reply, что сделал.
        Если это вопрос (например, когда пользователь свободен) — ответь коротко (1–2 предложения)
        по задачам и событиям выше и не добавляй и не меняй задач.
        \(Loc.isRussian ? "Отвечай по-русски." : "Answer in English; write task texts in English too.")
        """
        return [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "reply": ["type": "STRING", "description": "Короткий ответ пользователю"],
                        "tasks": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "text": ["type": "STRING"],
                                    "time": ["type": "STRING", "description": "ЧЧ:ММ или пустая строка"],
                                    "dates": ["type": "ARRAY", "items": ["type": "STRING"],
                                              "description": "Даты ГГГГ-ММ-ДД; пусто — открытый день"],
                                    "weeks": ["type": "INTEGER", "description": "Сколько недель повторять, 1 — без повтора"],
                                ],
                                "required": ["text"],
                            ],
                        ],
                        "changes": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "task": ["type": "STRING", "description": "Метка задачи: t1, t2…"],
                                    "action": ["type": "STRING", "enum": ["delete", "deleteSeries", "update", "done"]],
                                    "text": ["type": "STRING"],
                                    "time": ["type": "STRING", "description": "ЧЧ:ММ, «-» — убрать время"],
                                    "date": ["type": "STRING", "description": "ГГГГ-ММ-ДД"],
                                ],
                                "required": ["task", "action"],
                            ],
                        ],
                    ],
                    "required": ["reply", "tasks"],
                ],
            ],
        ]
    }

    private func send(body: [String: Any], key: String, models: [String], done: @escaping (Result) -> Void) {
        guard let model = models.first,
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(L("Gemini недоступен")))
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if [404, 429, 500, 503].contains(status), models.count > 1 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    self?.send(body: body, key: key, models: Array(models.dropFirst()), done: done)
                }
                return
            }
            if let error { return done(.failure(error.localizedDescription)) }
            if status == 200 { UserDefaults.standard.set(model, forKey: "gemini.lastModel") }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return done(.failure(L("Пустой ответ от Gemini")))
            }
            guard status == 200 else {
                let message = (json["error"] as? [String: Any])?["message"] as? String
                switch status {
                case 400, 401, 403:
                    return done(.failure(L("Ключ API не подошёл") + (message.map { ": \($0)" } ?? "")))
                case 429:
                    return done(.failure(L("Лимит бесплатных запросов исчерпан — попробуйте позже")))
                case 500, 503:
                    return done(.failure(L("Серверы Gemini сейчас перегружены — попробуйте через минуту")))
                case 404:
                    return done(.failure(L("Google сменил модели Gemini — обновите приложение")))
                default:
                    return done(.failure(message ?? L("Ошибка Gemini (%@)", "\(status)")))
                }
            }
            let text = ((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])
                .flatMap { $0["parts"] as? [[String: Any]] }?
                .compactMap { $0["text"] as? String }.joined() ?? ""
            guard let payload = text.data(using: .utf8),
                  let answer = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                return done(.success(Answer(reply: text, tasks: [])))
            }
            let tasks = (answer["tasks"] as? [[String: Any]] ?? []).compactMap { item -> SuggestedTask? in
                guard let text = item["text"] as? String, !text.isEmpty else { return nil }
                let time = (item["time"] as? String).flatMap { Self.normalizedTime($0) }
                let today = Calendar.current.startOfDay(for: Date())
                // Прошедшие даты модель иногда путает с будущими — такие отбрасываем.
                let days = (item["dates"] as? [String] ?? []).compactMap { Self.isoDay.date(from: $0) }.filter { $0 >= today }
                let weeks = min(max((item["weeks"] as? NSNumber)?.intValue ?? 1, 1), TaskParser.maxWeeks)
                return SuggestedTask(text: text, time: time, days: days, weeks: weeks)
            }
            let changes = (answer["changes"] as? [[String: Any]] ?? []).compactMap { item -> RawChange? in
                guard let ref = item["task"] as? String, let action = item["action"] as? String else { return nil }
                let rawTime = (item["time"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                return RawChange(ref: ref, action: action, text: item["text"] as? String,
                                 time: Self.normalizedTime(rawTime), clearTime: rawTime == "-",
                                 day: (item["date"] as? String).flatMap { Self.isoDay.date(from: $0) })
            }
            done(.success(Answer(reply: answer["reply"] as? String ?? "", tasks: tasks, changes: changes)))
        }.resume()
    }

    /// «9:5», «09:05», «17.00» → «09:05» / «17:00»; всё остальное отбрасываем.
    static func normalizedTime(_ raw: String) -> String? {
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return String(format: "%02d:%02d", parts[0], parts[1])
    }
}
