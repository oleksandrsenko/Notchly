import SwiftUI

/// `DynamicIsland --snapshots <папка>` рендерит все состояния острова в PNG —
/// удобно проверять вёрстку без записи экрана.
enum Snapshots {
    @MainActor
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = IslandModel()
        model.notchSize = CGSize(width: 185, height: 32)

        let art = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        model.media.debugSet(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                             duration: 200, elapsed: 74, playing: true, artwork: art, bundleID: "com.apple.Music")
        model.shelf.add([URL(fileURLWithPath: "/System/Applications/Music.app"),
                         URL(fileURLWithPath: "/etc/hosts")])

        let hosting = NSHostingView(rootView: IslandRootView(model: model, media: model.media))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: IslandMetrics.windowSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.85, alpha: 1)
        window.contentView = hosting

        func shot(_ name: String) {
            // Даём SwiftUI отработать изменения и анимации.
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }

        shot("1-compact")
        model.peek = true; shot("2-peek"); model.peek = false
        model.hud = HUDState(kind: .volume, value: 0.6); shot("3-hud"); model.hud = nil
        model.isExpanded = true
        for tab in IslandTab.allCases { model.tab = tab; shot("4-\(tab.rawValue)") }
        model.media.debugSet(title: "", artist: "", album: "", duration: 0, elapsed: 0, playing: false, artwork: nil, bundleID: nil)
        model.tab = .music; shot("5-empty")
    }
}
