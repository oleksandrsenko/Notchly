import AppKit
import SwiftUI
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case home, music, shelf, notes, controls, notifications
    var id: String { rawValue }

    /// Вкладки в шапке. Уведомления открываются колокольчиком справа.
    static let bar: [IslandTab] = [.home, .music, .shelf, .notes, .controls]

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .music: return "music.note"
        case .shelf: return "folder.fill"
        case .notes: return "note.text"
        case .controls: return "slider.horizontal.3"
        case .notifications: return "bell.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .music: return "Музыка"
        case .shelf: return "Файлы"
        case .notes: return "Заметки"
        case .controls: return "Управление"
        case .notifications: return "Уведомления"
        }
    }
}

/// Всплывающие события в стиле iPhone: подключили зарядку или наушники.
enum IslandEvent: Equatable {
    case charging(BatteryInfo)
    case device(DeviceBattery)
    case notification(AppNotification)

    var isDevice: Bool { if case .device = self { return true } else { return false } }

    var size: CGSize {
        switch self {
        case .charging: return IslandMetrics.eventSize
        case .device: return IslandMetrics.deviceSheetSize
        case .notification: return IslandMetrics.notificationSize
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .charging: return 32
        case .device: return 42
        case .notification: return 28
        }
    }

    var duration: TimeInterval {
        switch self {
        case .charging: return 4.5
        case .device: return 8
        case .notification: return 4
        }
    }
}

struct HUDState: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var value: Float
    var muted: Bool = false
}

enum IslandMetrics {
    static let expandedWidth: CGFloat = 640
    static let expandedContentHeight: CGFloat = 180
    static let compactWing: CGFloat = 40
    static let hudWing: CGFloat = 72
    static let peekWing: CGFloat = 56
    static let peekExtraHeight: CGFloat = 34
    static let eventSize = CGSize(width: 440, height: 118)
    static let deviceSheetSize = CGSize(width: 380, height: 236)
    static let notificationSize = CGSize(width: 430, height: 76)
    /// Запас окна вокруг острова, чтобы тень и пружинная анимация не обрезались.
    static let windowSize = CGSize(width: 760, height: 320)
    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.84)
    static let softSpring = Animation.spring(response: 0.55, dampingFraction: 0.9)
    /// Сворачивание: ширина, высота и содержимое уходят одновременно, одним плавным движением.
    static let collapse = Animation.spring(response: 0.38, dampingFraction: 1)
    /// Раскрытие «сверху вниз»: остров быстро расширяется вдоль верхней кромки и следом опускается.
    static let expandWidth = Animation.spring(response: 0.26, dampingFraction: 0.94)
    static let expandHeight = Animation.spring(response: 0.4, dampingFraction: 0.86)
    /// Сворачивание — обратное раскрытию: остров уходит вверх, а по ширине сужается чуть медленнее,
    /// поэтому движение читается как подъём, а не как схлопывание вбок.
    static let collapseHeight = Animation.spring(response: 0.34, dampingFraction: 1)
    static let collapseWidth = Animation.spring(response: 0.42, dampingFraction: 1)
}

final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    /// Раскрытое содержимое остаётся в иерархии, пока остров сворачивается, и убирается уже невидимым —
    /// иначе SwiftUI удаляет его вне общей раскладки, и оно «уезжает» вбок.
    @Published private(set) var expandedContentMounted = false
    private var unmountWork: DispatchWorkItem?
    @Published var tab: IslandTab {
        didSet {
            if tab == .notifications || oldValue == .notifications { markNotificationsSeen() }
            if tab != .notifications { UserDefaults.standard.set(tab.rawValue, forKey: "island.tab") }
        }
    }
    /// Всё, что пришло раньше этого момента, считается просмотренным (для счётчика на колокольчике).
    @Published private(set) var notificationsSeenAt =
        UserDefaults.standard.object(forKey: "notifications.seen") as? Date ?? .distantPast
    @Published var hud: HUDState?
    @Published var peek = false
    @Published var isDropTargeted = false
    /// Короткое уведомление «скопировано из …» по бокам выреза.
    @Published var clipPeek: ClipGroup?
    @Published var event: IslandEvent?
    /// Карточка события раскрыта. Сначала из выреза опускается «капля», потом она растекается в карточку.
    @Published var eventExpanded = false
    private var eventQueue: [IslandEvent] = []
    /// Ширина и высота острова анимируются раздельно — так раскрытие идёт сверху вниз.
    private(set) var widthAnimation = IslandMetrics.softSpring
    private(set) var heightAnimation = IslandMetrics.softSpring

    private func animateSize(_ width: Animation, _ height: Animation? = nil) {
        widthAnimation = width
        heightAnimation = height ?? width
    }
    /// Пока курсор над карточкой события, она не закрывается сама.
    var eventHovered = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasPhysicalNotch = true

    let media = MediaController()
    let volume = VolumeController()
    let brightness = BrightnessController()
    let mixer = AppAudioMixer()
    let shelf = ShelfStore()
    let notes = NotesStore()
    let clipboard: ClipboardMonitor
    let tasks: TasksStore
    let gemini = GeminiAssistant()
    let batteries = DeviceBatteryMonitor()
    let keys = MediaKeyInterceptor()
    let weather = WeatherService()
    let vault = KeyVault()
    let gmail = GmailClient()
    let systemNotifications = SystemNotificationsReader()

    private var hudTask: DispatchWorkItem?
    private var peekTask: DispatchWorkItem?
    private var clipTask: DispatchWorkItem?
    private var eventTask: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    /// persistent = false — для снапшотов: ничего не читаем и не пишем на диск.
    init(persistent: Bool = true) {
        clipboard = ClipboardMonitor(persistent: persistent)
        tasks = TasksStore(persistent: persistent)
        tab = IslandTab(rawValue: UserDefaults.standard.string(forKey: "island.tab") ?? "") ?? .home

        keys.handler = { [weak self] key, fine in self?.handleKey(key, fine: fine) }
        clipboard.onCopy = { [weak self] group in self?.showClipPeek(group) }
        batteries.onChargerConnected = { [weak self] info in self?.showEvent(.charging(info)) }
        batteries.onAudioDeviceConnected = { [weak self] device in self?.showEvent(.device(device)) }
        systemNotifications.onNew = { [weak self] item in self?.showEvent(.notification(item)) }
        gmail.onNew = { [weak self] mail in
            self?.showEvent(.notification(AppNotification(
                id: "gmail-\(mail.id)", bundleID: AppNotification.gmailID, title: mail.senderName,
                subtitle: "", body: mail.subject, date: mail.date)))
        }

        volume.onExternalChange = { [weak self] value, muted in
            self?.showHUD(HUDState(kind: .volume, value: value, muted: muted))
        }
        brightness.onExternalChange = { [weak self] value in
            self?.showHUD(HUDState(kind: .brightness, value: value))
        }
        media.onTrackChange = { [weak self] in self?.trackChanged() }

        // Пересчитываем форму острова, когда меняется состояние плеера.
        media.$showsLiveActivity
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    // MARK: - Геометрия

    var topRadius: CGFloat { isExpanded ? 14 : 7 }

    var bottomRadius: CGFloat {
        if isExpanded { return 34 }
        if let event { return eventExpanded ? event.bottomRadius : 22 }
        if peek && media.hasTrack { return 20 }
        return hasPhysicalNotch ? 11 : 14
    }

    /// Размер «тела» острова без боковых изгибов у верхней кромки.
    var bodySize: CGSize {
        let n = notchSize
        if isExpanded {
            return CGSize(width: IslandMetrics.expandedWidth, height: n.height + IslandMetrics.expandedContentHeight)
        }
        if let event {
            if !eventExpanded {
                return CGSize(width: n.width + 18, height: n.height + 24)
            }
            let size = event.size
            return CGSize(width: size.width, height: n.height + size.height)
        }
        if hud != nil || clipPeek != nil {
            return CGSize(width: n.width + IslandMetrics.hudWing * 2, height: n.height)
        }
        if peek && media.hasTrack {
            return CGSize(width: n.width + IslandMetrics.peekWing * 2, height: n.height + IslandMetrics.peekExtraHeight)
        }
        if media.showsLiveActivity {
            return CGSize(width: n.width + IslandMetrics.compactWing * 2, height: n.height)
        }
        return n
    }

    /// Полный размер фигуры с учётом изгибов у верхней кромки.
    var shapeSize: CGSize {
        CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height)
    }

    // MARK: - Состояния

    private func markNotificationsSeen() {
        notificationsSeenAt = Date()
        UserDefaults.standard.set(notificationsSeenAt, forKey: "notifications.seen")
    }

    func expand(to tab: IslandTab? = nil) {
        if let tab {
            self.tab = tab
        } else if !isExpanded {
            // Каждое открытие начинается с главной.
            self.tab = .home
        }
        guard !isExpanded else { return }
        hud = nil
        peek = false
        clipPeek = nil
        event = nil
        eventExpanded = false
        eventQueue.removeAll()
        if self.tab == .home {
            batteries.refresh()
            weather.refresh()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        unmountWork?.cancel()
        expandedContentMounted = true
        animateSize(IslandMetrics.expandWidth, IslandMetrics.expandHeight)
        withAnimation(IslandMetrics.expandHeight) { isExpanded = true }
    }

    func collapse() {
        guard isExpanded else { return }
        vault.lock()
        animateSize(IslandMetrics.collapseWidth, IslandMetrics.collapseHeight)
        withAnimation(IslandMetrics.collapseHeight) { isExpanded = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.expandedContentMounted = false
        }
        unmountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func showEvent(_ event: IslandEvent) {
        guard !isExpanded else { return }
        // Пока показана одна карточка, следующие уведомления ждут своей очереди.
        if self.event != nil, case .notification = event {
            eventQueue.append(event)
            return
        }
        eventTask?.cancel()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        // «Капля»: сначала узкая капля выпадает из выреза…
        eventExpanded = false
        animateSize(.spring(response: 0.34, dampingFraction: 0.72))
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            hud = nil
            peek = false
            clipPeek = nil
            self.event = event
        }
        // …и почти сразу мягко растекается в карточку.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.event == event else { return }
            self.animateSize(.spring(response: 0.3, dampingFraction: 0.9), .spring(response: 0.5, dampingFraction: 0.84))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { self.eventExpanded = true }
        }
        scheduleEventDismiss(after: event.duration + 0.2)
    }

    private func scheduleEventDismiss(after delay: TimeInterval) {
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.eventHovered { return self.scheduleEventDismiss(after: 1) }
            self.hideEvent()
        }
        eventTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func dismissEvent() {
        eventTask?.cancel()
        eventHovered = false
        hideEvent()
    }

    /// Сворачиваем карточку обратно в вырез и показываем следующую из очереди.
    private func hideEvent() {
        animateSize(IslandMetrics.collapse)
        withAnimation(IslandMetrics.collapse) {
            eventExpanded = false
            event = nil
        }
        guard !eventQueue.isEmpty else { return }
        let next = eventQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.showEvent(next) }
    }

    func showHUD(_ state: HUDState) {
        guard !isExpanded, event == nil else { return }
        hudTask?.cancel()
        animateSize(IslandMetrics.spring)
        withAnimation(IslandMetrics.spring) {
            peek = false
            clipPeek = nil
            hud = state
        }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.hud = nil }
        }
        hudTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private func handleKey(_ key: MediaKeyInterceptor.Key, fine: Bool) {
        switch key {
        case .volumeUp, .volumeDown:
            volume.step(up: key == .volumeUp, fine: fine)
        case .mute:
            volume.toggleMute()
        case .brightnessUp, .brightnessDown:
            brightness.step(up: key == .brightnessUp, fine: fine)
        }
        switch key {
        case .volumeUp, .volumeDown, .mute:
            showHUD(HUDState(kind: .volume, value: volume.volume, muted: volume.isMuted))
        case .brightnessUp, .brightnessDown:
            showHUD(HUDState(kind: .brightness, value: brightness.brightness))
        }
    }

    func showClipPeek(_ group: ClipGroup) {
        guard !isExpanded, hud == nil, event == nil else { return }
        clipTask?.cancel()
        animateSize(IslandMetrics.spring)
        withAnimation(IslandMetrics.spring) {
            peek = false
            clipPeek = group
        }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.clipPeek = nil }
        }
        clipTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }

    private var peekedID = ""
    private var trackChangeWork: DispatchWorkItem?

    /// Плееры присылают название, исполнителя и альбом не всегда одним сообщением.
    /// Ждём, пока данные устоятся, и показываем шторку один раз на трек.
    private func trackChanged() {
        trackChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.media.hasTrack, self.media.peekID != self.peekedID else { return }
            self.peekedID = self.media.peekID
            self.showPeek()
        }
        trackChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func showPeek() {
        guard !isExpanded, hud == nil, event == nil, media.hasTrack else { return }
        peekTask?.cancel()
        animateSize(IslandMetrics.softSpring)
        if !peek { withAnimation(IslandMetrics.softSpring) { peek = true } }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.peek = false }
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: task)
    }
}
