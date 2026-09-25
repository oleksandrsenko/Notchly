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
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
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
                    if items != self.notifications { self.notifications = items }
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
