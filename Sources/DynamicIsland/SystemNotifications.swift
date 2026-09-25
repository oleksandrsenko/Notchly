import AppKit
import SQLite3

struct AppNotification: Identifiable, Equatable {
    var id: String
    var bundleID: String
    var title: String
    var subtitle: String
    var body: String
    var date: Date
}

/// Уведомления других приложений (Telegram, WhatsApp и т. д.) из базы Центра уведомлений macOS.
/// Чтобы её читать, приложению нужен «Полный доступ к диску».
final class SystemNotificationsReader: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var needsFullDiskAccess = false

    /// Пришло новое уведомление — остров показывает его карточкой.
    var onNew: ((AppNotification) -> Void)?

    /// Базу Центра уведомлений мы только читаем, поэтому «удалённое» просто скрываем у себя.
    private var raw: [AppNotification] = []
    private var dismissedIDs = Set(UserDefaults.standard.stringArray(forKey: "notifications.dismissed") ?? [])
    private var clearedBefore = (UserDefaults.standard.dictionary(forKey: "notifications.clearedBefore") as? [String: Date]) ?? [:]
    private var newestSeen: Date?

    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path
    private var timer: Timer?
    private var lastModified: Date?

    /// Сами себе уведомления не показываем, как и служебные системные.
    private static let ignored: Set<String> = [
        "dev.aleksandrsenko.DynamicIsland", "com.apple.controlcenter", "_system_center_",
    ]

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Для снапшотов.
    func debugSet(_ items: [AppNotification]) {
        timer?.invalidate()
        needsFullDiskAccess = false
        raw = items
        dismissedIDs = []
        clearedBefore = [:]
        notifications = items
    }

    func dismiss(_ item: AppNotification) {
        dismissedIDs.insert(item.id)
        persistDismissed()
    }

    func dismissAll(bundleID: String) {
        clearedBefore[bundleID] = raw.filter { $0.bundleID == bundleID }.map(\.date).max() ?? Date()
        persistDismissed()
    }

    func dismissAll() {
        for bundleID in Set(raw.map(\.bundleID)) { dismissAll(bundleID: bundleID) }
    }

    private func persistDismissed() {
        // Храним только id, которые ещё есть в базе, чтобы список не рос бесконечно.
        let alive = Set(raw.map(\.id))
        dismissedIDs = dismissedIDs.filter(alive.contains)
        UserDefaults.standard.set(Array(dismissedIDs), forKey: "notifications.dismissed")
        UserDefaults.standard.set(clearedBefore, forKey: "notifications.clearedBefore")
        applyFilter()
    }

    private func applyFilter() {
        let visible = raw.filter { item in
            !dismissedIDs.contains(item.id) && item.date > (clearedBefore[item.bundleID] ?? .distantPast)
        }
        if visible != notifications { notifications = visible }
    }

    private func announceNew(_ items: [AppNotification]) {
        let newest = items.map(\.date).max()
        defer { if let newest { newestSeen = max(newestSeen ?? newest, newest) } }
        // При первом чтении базы ничего не показываем — это старые уведомления.
        guard let seen = newestSeen,
              let fresh = items.filter({ $0.date > seen && Date().timeIntervalSince($0.date) < 60 })
                .max(by: { $0.date < $1.date }) else { return }
        onNew?(fresh)
    }

    private func reloadIfChanged() {
        // База пишется в WAL-файл, поэтому смотрим на оба.
        let dates = [path, path + "-wal"].compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
        }
        let newest = dates.max()
        guard needsFullDiskAccess || newest != lastModified else { return }
        lastModified = newest
        reload()
    }

    private func reload() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.read()
            DispatchQueue.main.async {
                switch result {
                case .none:
                    self.needsFullDiskAccess = true
                case .some(let items):
                    self.needsFullDiskAccess = false
                    self.raw = items
                    self.announceNew(items)
                    self.applyFilter()
                }
            }
        }
    }

    private func read() -> [AppNotification]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT record.rec_id, app.identifier, record.data, record.delivered_date
        FROM record JOIN app ON app.app_id = record.app_id
        ORDER BY record.delivered_date DESC LIMIT 300
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var items: [AppNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let recID = sqlite3_column_int64(stmt, 0)
            guard let idPtr = sqlite3_column_text(stmt, 1) else { continue }
            let bundleID = String(cString: idPtr)
            guard !Self.ignored.contains(bundleID) else { continue }
            let length = Int(sqlite3_column_bytes(stmt, 2))
            guard length > 0, let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let data = Data(bytes: blob, count: length)
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            let title = req["titl"] as? String ?? ""
            let body = req["body"] as? String ?? ""
            guard !title.isEmpty || !body.isEmpty else { continue }
            let delivered = sqlite3_column_double(stmt, 3)
            items.append(AppNotification(id: "\(recID)", bundleID: bundleID, title: title,
                                         subtitle: req["subt"] as? String ?? "", body: body,
                                         date: Date(timeIntervalSinceReferenceDate: delivered)))
        }
        return items
    }
}
