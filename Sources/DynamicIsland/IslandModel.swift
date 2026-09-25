import AppKit
import SwiftUI
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case home, music, shelf, notes, controls
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .music: return "music.note"
        case .shelf: return "tray.full.fill"
        case .notes: return "note.text"
        case .controls: return "slider.horizontal.3"
        }
    }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .music: return "Музыка"
        case .shelf: return "Полка"
        case .notes: return "Заметки"
        case .controls: return "Управление"
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
    /// Запас окна вокруг острова, чтобы тень и пружинная анимация не обрезались.
    static let windowSize = CGSize(width: 760, height: 320)
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let softSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)
}

final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    @Published var tab: IslandTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "island.tab") }
    }
    @Published var hud: HUDState?
    @Published var peek = false
    @Published var isDropTargeted = false
    /// Короткое уведомление «скопировано из …» по бокам выреза.
    @Published var clipPeek: ClipGroup?
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasPhysicalNotch = true

    let media = MediaController()
    let volume = VolumeController()
    let brightness = BrightnessController()
    let shelf = ShelfStore()
    let notes = NotesStore()
    let clipboard = ClipboardMonitor()
    let batteries = DeviceBatteryMonitor()
    let keys = MediaKeyInterceptor()

    private var hudTask: DispatchWorkItem?
    private var peekTask: DispatchWorkItem?
    private var clipTask: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init() {
        tab = IslandTab(rawValue: UserDefaults.standard.string(forKey: "island.tab") ?? "") ?? .home

        keys.handler = { [weak self] key, fine in self?.handleKey(key, fine: fine) }
        clipboard.onCopy = { [weak self] group in self?.showClipPeek(group) }

        volume.onExternalChange = { [weak self] value, muted in
            self?.showHUD(HUDState(kind: .volume, value: value, muted: muted))
        }
        brightness.onExternalChange = { [weak self] value in
            self?.showHUD(HUDState(kind: .brightness, value: value))
        }
        media.onTrackChange = { [weak self] in self?.showPeek() }

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
        if peek && media.hasTrack { return 20 }
        return hasPhysicalNotch ? 11 : 14
    }

    /// Размер «тела» острова без боковых изгибов у верхней кромки.
    var bodySize: CGSize {
        let n = notchSize
        if isExpanded {
            return CGSize(width: IslandMetrics.expandedWidth, height: n.height + IslandMetrics.expandedContentHeight)
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

    func expand(to tab: IslandTab? = nil) {
        if let tab { self.tab = tab }
        guard !isExpanded else { return }
        hud = nil
        peek = false
        clipPeek = nil
        if tab == .home { batteries.refresh() }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(IslandMetrics.spring) { isExpanded = true }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(IslandMetrics.softSpring) { isExpanded = false }
    }

    func showHUD(_ state: HUDState) {
        guard !isExpanded else { return }
        hudTask?.cancel()
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
        guard !isExpanded, hud == nil else { return }
        clipTask?.cancel()
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

    func showPeek() {
        guard !isExpanded, hud == nil, media.hasTrack else { return }
        peekTask?.cancel()
        withAnimation(IslandMetrics.spring) { peek = true }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.peek = false }
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: task)
    }
}
