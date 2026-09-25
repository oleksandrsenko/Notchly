import Foundation

/// Небольшой помощник на Gemini API: превращает фразу вроде «сегодня в 5 спортзал, в 10 созвон»
/// в задачи и коротко отвечает на вопросы. Ключ API хранится в Связке ключей.
final class GeminiAssistant: ObservableObject {
    struct SuggestedTask { var text: String; var time: String? }

    @Published private(set) var hasKey = false
    @Published private(set) var isThinking = false
    @Published private(set) var reply: String?
    @Published private(set) var error: String?

    private static let service = "gemini"
    private static let account = "api-key"
    /// Сначала «последняя flash», если Google её не отдаёт — фиксированная версия.
    private static let models = ["gemini-flash-latest", "gemini-2.5-flash"]

    init() {
        hasKey = Keychain.data(service: Self.service, account: Self.account) != nil
    }

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasKey = Keychain.set(Data(trimmed.utf8), service: Self.service, account: Self.account)
        error = hasKey ? nil : "Не удалось сохранить ключ в Связке ключей"
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

    func ask(_ prompt: String, tasks: [TaskItem], completion: @escaping ([SuggestedTask]) -> Void) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking,
              let keyData = Keychain.data(service: Self.service, account: Self.account),
              let key = String(data: keyData, encoding: .utf8) else { return }
        isThinking = true
        error = nil
        reply = nil
        let body = Self.requestBody(for: text, tasks: tasks)
        send(body: body, key: key, models: Self.models) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isThinking = false
                switch result {
                case .success(let answer):
                    self.reply = answer.reply.isEmpty ? nil : answer.reply
                    completion(answer.tasks)
                case .failure(let message):
                    self.error = message
                }
            }
        }
    }

    // MARK: - Запрос

    private struct Answer { var reply: String; var tasks: [SuggestedTask] }
    private enum Failure: Error { case message(String) }
    private enum Result { case success(Answer), failure(String) }

    private static func requestBody(for text: String, tasks: [TaskItem]) -> [String: Any] {
        let now = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()
            .locale(Locale(identifier: "ru_RU")))
        let current = tasks.filter { !$0.done }
            .map { "- " + ($0.time.map { "\($0) " } ?? "") + $0.text }
            .joined(separator: "\n")
        let system = """
        Ты — компактный помощник в Dynamic Island на Mac. Сейчас \(now).
        Текущие задачи пользователя:
        \(current.isEmpty ? "(нет)" : current)

        Если пользователь описывает планы или дела — разбей их на короткие задачи (до 60 символов,
        начинаются с глагола или существительного, без времени в тексте). Время укажи отдельно в формате ЧЧ:ММ
        в 24-часовом формате; «в 5» днём/вечером — это 17:00, «в 10» утром — 10:00, если из контекста не ясно иное.
        Если это вопрос — ответь коротко (1–2 предложения) и не добавляй задач.
        Отвечай по-русски.
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
                                ],
                                "required": ["text"],
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
            return done(.failure("Gemini недоступен"))
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404, models.count > 1 {
                self?.send(body: body, key: key, models: Array(models.dropFirst()), done: done)
                return
            }
            if let error { return done(.failure(error.localizedDescription)) }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return done(.failure("Пустой ответ от Gemini"))
            }
            guard status == 200 else {
                let message = (json["error"] as? [String: Any])?["message"] as? String
                return done(.failure(status == 400 || status == 403
                                     ? "Ключ API не подошёл" + (message.map { ": \($0)" } ?? "")
                                     : message ?? "Ошибка Gemini (\(status))"))
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
                return SuggestedTask(text: text, time: time)
            }
            done(.success(Answer(reply: answer["reply"] as? String ?? "", tasks: tasks)))
        }.resume()
    }

    /// «9:5», «09:05», «17.00» → «09:05» / «17:00»; всё остальное отбрасываем.
    static func normalizedTime(_ raw: String) -> String? {
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return String(format: "%02d:%02d", parts[0], parts[1])
    }
}
