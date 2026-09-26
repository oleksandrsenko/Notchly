import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// Место вкладки в шапке: сторона от выреза и видимость.
struct TabSlot: Codable, Equatable, Identifiable {
    enum Side: String, Codable { case leading, trailing }
    var tab: IslandTab
    var side: Side
    var visible = true
    var id: IslandTab { tab }
}

/// Все настройки, которые пользователь меняет в окне «Настройки». Хранятся в UserDefaults.
/// persistent = false — для снапшотов: значения по умолчанию, ничего не читаем и не пишем.
final class AppSettings: ObservableObject {
    /// Раскладка шапки по умолчанию: слева то, чем пользуются постоянно, справа — «инструменты».
    static let defaultTabs: [TabSlot] = [
        TabSlot(tab: .home, side: .leading), TabSlot(tab: .music, side: .leading),
        TabSlot(tab: .notes, side: .leading), TabSlot(tab: .timer, side: .leading),
        TabSlot(tab: .clipboard, side: .trailing), TabSlot(tab: .shelf, side: .trailing),
        TabSlot(tab: .controls, side: .trailing),
    ]
    static let closeDelayRange: ClosedRange<Double> = 0.3...5

    @Published var tabs: [TabSlot] { didSet { save(tabs, "settings.tabs") } }
    /// Через сколько секунд остров закрывается, если курсор ушёл с него (клик мимо закрывает сразу).
    @Published var closeDelay: Double { didSet { store(closeDelay, "settings.closeDelay") } }
    /// Открывать остров на главной (иначе — на последней вкладке).
    @Published var openOnHome: Bool { didSet { store(openOnHome, "settings.openOnHome") } }

    @Published var musicActivity: Bool { didSet { store(musicActivity, "settings.musicActivity") } }
    @Published var trackPeek: Bool { didSet { store(trackPeek, "settings.trackPeek") } }
    @Published var hud: Bool { didSet { store(hud, "settings.hud") } }
    @Published var copiedPeek: Bool { didSet { store(copiedPeek, "settings.copiedPeek") } }
    @Published var chargingCard: Bool { didSet { store(chargingCard, "settings.chargingCard") } }
    @Published var headphonesCard: Bool { didSet { store(headphonesCard, "settings.headphonesCard") } }

    @Published var appNotifications: Bool { didSet { store(appNotifications, "settings.appNotifications") } }
    @Published var gmailNotifications: Bool { didSet { store(gmailNotifications, "settings.gmailNotifications") } }
    @Published var reminders: Bool { didSet { store(reminders, "settings.reminders") } }
    @Published var sounds: Bool { didSet { store(sounds, "settings.sounds") } }

    @Published var clipboardHistory: Bool { didSet { store(clipboardHistory, "settings.clipboardHistory") } }
    @Published var screenshots: Bool { didSet { store(screenshots, "settings.screenshots") } }
    /// Брать и снимки, которые macOS сохраняет файлами (на рабочий стол). Спросит доступ к папке.
    @Published var screenshotFiles: Bool { didSet { store(screenshotFiles, "settings.screenshotFiles") } }
    @Published var menuBarIcon: Bool { didSet { store(menuBarIcon, "settings.menuBarIcon") } }
    /// Язык интерфейса. Строки берутся через L(...), поэтому смена видна сразу.
    @Published var language: AppLanguage {
        didSet {
            Loc.language = language
            store(language.rawValue, "settings.language")
        }
    }

    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool { persistent ? (d.object(forKey: key) as? Bool ?? fallback) : fallback }
        let savedTabs = persistent ? d.data(forKey: "settings.tabs").flatMap { try? JSONDecoder().decode([TabSlot].self, from: $0) } : nil
        tabs = Self.normalized(savedTabs ?? Self.defaultTabs)
        closeDelay = persistent ? (d.object(forKey: "settings.closeDelay") as? Double ?? 1.2) : 1.2
        openOnHome = bool("settings.openOnHome", true)
        musicActivity = bool("settings.musicActivity", true)
        trackPeek = bool("settings.trackPeek", true)
        hud = bool("settings.hud", true)
        copiedPeek = bool("settings.copiedPeek", true)
        chargingCard = bool("settings.chargingCard", true)
        headphonesCard = bool("settings.headphonesCard", true)
        appNotifications = bool("settings.appNotifications", true)
        gmailNotifications = bool("settings.gmailNotifications", true)
        reminders = bool("settings.reminders", true)
        sounds = bool("settings.sounds", true)
        clipboardHistory = bool("settings.clipboardHistory", true)
        screenshots = bool("settings.screenshots", true)
        screenshotFiles = bool("settings.screenshotFiles", false)
        menuBarIcon = bool("settings.menuBarIcon", true)
        // Снапшоты рендерятся на языке, заданном до создания модели (--lang).
        language = persistent
            ? (d.string(forKey: "settings.language").flatMap(AppLanguage.init(rawValue:)) ?? .system)
            : Loc.language
        Loc.language = language
    }

    /// Сохранённая раскладка могла появиться до новой вкладки — дописываем недостающие, убираем лишние.
    static func normalized(_ slots: [TabSlot]) -> [TabSlot] {
        var result = slots.filter { $0.tab != .notifications }
        var seen = Set<IslandTab>()
        result = result.filter { seen.insert($0.tab).inserted }
        for slot in defaultTabs where !seen.contains(slot.tab) { result.append(slot) }
        // Главная всегда видна: на неё остров возвращается при повторном нажатии на вкладку.
        if let i = result.firstIndex(where: { $0.tab == .home }) { result[i].visible = true }
        return result
    }

    func tabs(on side: TabSlot.Side) -> [IslandTab] {
        tabs.filter { $0.side == side && $0.visible }.map(\.tab)
    }

    /// Порядок видимых вкладок слева направо — от него зависит направление перелистывания.
    var visibleOrder: [IslandTab] { tabs(on: .leading) + tabs(on: .trailing) + [.notifications] }

    func isVisible(_ tab: IslandTab) -> Bool {
        tab == .notifications || tabs.first { $0.tab == tab }?.visible == true
    }

    func resetTabs() { tabs = Self.defaultTabs }

    // MARK: - Запуск при входе

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error)")
            }
        }
    }

    // MARK: - Хранение

    private func store(_ value: Any, _ key: String) {
        guard persistent else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard persistent, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
