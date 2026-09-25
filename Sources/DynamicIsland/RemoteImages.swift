import AppKit

/// Картинки из интернета: иконки музыкальных сервисов и обложки треков из iTunes Search API.
/// Всё кэшируется в памяти, ответы — на главном потоке.
enum RemoteImages {
    private static var cache: [String: NSImage] = [:]
    private static var pending: [String: [(NSImage?) -> Void]] = [:]

    /// Иконка iOS-версии приложения по bundle id (App Store есть не во всех странах, поэтому пробуем несколько).
    static func appIcon(bundleID: String, completion: @escaping (NSImage?) -> Void) {
        load(key: "app:\(bundleID)", completion: completion) { done in
            lookup(bundleID: bundleID, countries: ["us", "ru"], done: done)
        }
    }

    /// Обложка трека, если плеер её не прислал.
    static func artwork(title: String, artist: String, completion: @escaping (NSImage?) -> Void) {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return completion(nil) }
        load(key: "art:\(term.lowercased())", completion: completion) { done in
            var comps = URLComponents(string: "https://itunes.apple.com/search")!
            comps.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "song"),
                                .init(name: "limit", value: "1")]
            fetchJSON(comps.url!) { json in
                let results = json?["results"] as? [[String: Any]]
                guard let small = results?.first?["artworkUrl100"] as? String,
                      let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
                else { return done(nil) }
                fetchImage(url, done: done)
            }
        }
    }

    // MARK: - Внутреннее

    private static func load(key: String, completion: @escaping (NSImage?) -> Void,
                             fetch: (@escaping (NSImage?) -> Void) -> Void) {
        if let cached = cache[key] { return completion(cached) }
        if pending[key] != nil { pending[key]?.append(completion); return }
        pending[key] = [completion]
        fetch { image in
            DispatchQueue.main.async {
                if let image { cache[key] = image }
                pending.removeValue(forKey: key)?.forEach { $0(image) }
            }
        }
    }

    private static func lookup(bundleID: String, countries: [String], done: @escaping (NSImage?) -> Void) {
        guard let country = countries.first else { return done(nil) }
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=\(country)")!
        fetchJSON(url) { json in
            let results = json?["results"] as? [[String: Any]]
            if let icon = results?.first?["artworkUrl512"] as? String, let iconURL = URL(string: icon) {
                fetchImage(iconURL, done: done)
            } else {
                lookup(bundleID: bundleID, countries: Array(countries.dropFirst()), done: done)
            }
        }
    }

    private static func fetchJSON(_ url: URL, done: @escaping ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            done(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    private static func fetchImage(_ url: URL, done: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            done(data.flatMap(NSImage.init(data:)))
        }.resume()
    }
}
