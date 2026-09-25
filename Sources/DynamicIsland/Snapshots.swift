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

        model.clipboard.add(text: "git commit -m fix", bundleID: "com.apple.Terminal", appName: "Терминал")
        model.clipboard.add(text: "Привет! Сделай мне Dynamic Island", bundleID: "com.anthropic.claudefordesktop", appName: "Claude")
        model.clipboard.add(text: "https://music.yandex.ru", bundleID: "com.google.Chrome", appName: "Google Chrome")
        model.clipboard.add(text: "Вторая строка из Claude", bundleID: "com.anthropic.claudefordesktop", appName: "Claude")
        model.clipPeek = nil; model.peek = false

        shot("1-compact")
        model.clipPeek = model.clipboard.groups.first; shot("2-clip"); model.clipPeek = nil
        model.peek = true; shot("2-peek"); model.peek = false
        model.hud = HUDState(kind: .volume, value: 0.6); shot("3-hud"); model.hud = nil
        model.isExpanded = true
        let clipHost = NSHostingView(rootView: ClipboardView(clipboard: model.clipboard)
            .frame(width: 596, height: 130).padding(20).background(Color.black).preferredColorScheme(.dark))
        clipHost.frame = NSRect(x: 0, y: 0, width: 636, height: 170)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = clipHost.bitmapImageRepForCachingDisplay(in: clipHost.bounds) {
            clipHost.cacheDisplay(in: clipHost.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("6-clipboard.png"))
        }
        for tab in IslandTab.allCases { model.tab = tab; shot("4-\(tab.rawValue)") }
        model.media.debugSet(title: "", artist: "", album: "", duration: 0, elapsed: 0, playing: false, artwork: nil, bundleID: nil)
        model.tab = .music; shot("5-empty")
    }
}
