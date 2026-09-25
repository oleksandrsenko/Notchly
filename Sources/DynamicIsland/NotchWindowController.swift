import AppKit
import SwiftUI

/// Прозрачная панель поверх строки меню. Не активирует приложение,
/// но может стать key-окном, чтобы в заметках работал ввод текста.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchWindowController {
    let model = IslandModel()
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    init() {
        let root = IslandRootView(model: model, media: model.media)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.layout()
        }
    }

    // MARK: - Размещение

    private func layout() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            model.notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            model.hasPhysicalNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(26, menuBar))
            model.hasPhysicalNotch = false
        }

        let size = IslandMetrics.windowSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }

    /// Текущая область острова в экранных координатах.
    private func islandRect() -> NSRect {
        let size = model.shapeSize
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: - Мышь

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.handleMouse(dragging: event.type == .leftMouseDragged)
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.handleMouse(dragging: false)
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.dragChangeCount = NSPasteboard(name: .drag).changeCount
            if self.model.isExpanded && !self.islandRect().contains(NSEvent.mouseLocation) {
                self.model.collapse()
                self.syncMouseEvents(inHotZone: false)
            }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouse(dragging: false)
        } as Any)
    }

    private func handleMouse(dragging: Bool) {
        let location = NSEvent.mouseLocation
        guard screen.frame.contains(location) || islandRect().contains(location) else {
            scheduleCollapseIfNeeded()
            return
        }

        if model.isExpanded {
            if islandRect().insetBy(dx: -12, dy: -12).contains(location) {
                collapseWork?.cancel()
                collapseWork = nil
            } else {
                scheduleCollapseIfNeeded()
            }
            syncMouseEvents(inHotZone: true)
            return
        }

        // В свёрнутом состоянии зона срабатывания чуть шире самого выреза.
        let hot = islandRect().insetBy(dx: -10, dy: -4)
        let inHot = hot.contains(location)
        syncMouseEvents(inHotZone: inHot)

        guard inHot else {
            expandWork?.cancel()
            expandWork = nil
            return
        }

        if dragging {
            let drag = NSPasteboard(name: .drag)
            let isFileDrag = drag.changeCount != dragChangeCount &&
                (drag.types?.contains(.fileURL) ?? false)
            if isFileDrag { model.expand(to: .shelf) }
            return
        }

        guard expandWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            if self.islandRect().insetBy(dx: -10, dy: -4).contains(NSEvent.mouseLocation) {
                self.model.expand()
                self.syncMouseEvents(inHotZone: true)
            }
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }

    private func scheduleCollapseIfNeeded() {
        guard model.isExpanded, collapseWork == nil else { return }
        // Не сворачиваем, пока пользователь тянет слайдер или файл.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            let inside = self.islandRect().insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation)
            if !inside && NSEvent.pressedMouseButtons == 0 {
                self.model.collapse()
                self.syncMouseEvents(inHotZone: false)
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func syncMouseEvents(inHotZone: Bool) {
        let shouldIgnore = !(model.isExpanded || inHotZone)
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }
}
