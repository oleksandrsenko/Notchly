import SwiftUI

/// Начальные состояния отдельных экранов — только для снапшотов.
enum SnapshotFlags {
    static var batteryPage = 0
    static var openedTask: UUID?
    static var notesMode: NotesView.Mode = .notes
}

/// `Notchly --snapshots <папка>` рендерит все состояния острова в PNG —
/// удобно проверять вёрстку без записи экрана.
enum Snapshots {
    @MainActor
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = IslandModel(persistent: false)
        model.notchSize = CGSize(width: 185, height: 32)

        let art = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        model.media.debugSet(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                             duration: 200, elapsed: 74, playing: true, artwork: art, bundleID: "com.apple.Music")
        model.weather.debugSet(Weather(temperature: 18, high: 21, low: 12, code: 1, isDay: true, city: "Берлин",
                                       latitude: 52.52, longitude: 13.40))
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
        model.clipboard.add(text: "Привет! Сделай мне остров в вырезе", bundleID: "com.anthropic.claudefordesktop", appName: "Claude")
        model.clipboard.add(text: "https://music.yandex.ru", bundleID: "com.google.Chrome", appName: "Google Chrome")
        model.clipboard.add(text: "Вторая строка из Claude", bundleID: "com.anthropic.claudefordesktop", appName: "Claude")
        model.clipPeek = nil; model.peek = false

        shot("1-compact")
        model.clipPeek = model.clipboard.groups.first; shot("2-clip"); model.clipPeek = nil
        model.peek = true; shot("2-peek"); model.peek = false
        model.hud = HUDState(kind: .volume, value: 0.6); shot("3-hud"); model.hud = nil
        model.eventExpanded = true; model.event = .charging(BatteryInfo(percent: 82, charging: true, onAC: true)); shot("7-charging")
        model.event = .device(DeviceBattery(name: "AirPods Pro (Alexander)", symbol: "airpodspro", levels: [
            .init(label: "Левый", symbol: "airpod.left", percent: 100, charging: true),
            .init(label: "Правый", symbol: "airpod.right", percent: 100, charging: true),
            .init(label: "Кейс", symbol: "airpodspro.chargingcase.wireless.fill", percent: 20)])); shot("8-airpods")
        model.event = .device(DeviceBattery(name: "AirPods Pro", symbol: "airpodspro", levels: [
            .init(label: "Левый", symbol: "airpod.left", percent: 100),
            .init(label: "Правый", symbol: "airpod.right", percent: 64),
            .init(label: "Кейс", symbol: "airpodspro.chargingcase.wireless.fill", percent: 40)])); shot("8-airpods-split")
        model.event = .device(DeviceBattery(name: "AirPods Max", symbol: "airpodsmax", levels: [
            .init(label: "", symbol: "", percent: 64)])); shot("9-max")
        model.event = .notification(AppNotification(id: "1", bundleID: "ru.keepcoder.Telegram", title: "Мама",
                                                    subtitle: "", body: "Ты сегодня приедешь на ужин? Я приготовлю твой любимый пирог 🥧",
                                                    date: Date())); shot("10-notification")
        model.event = .reminder(Reminder(id: "r", title: "Немецкий — урок 12", date: Date().addingTimeInterval(600),
                                         minutesBefore: 10, source: .task, link: URL(string: "https://zoom.us/j/123"))); shot("10-reminder")
        model.event = .reminder(Reminder(id: "c", title: "Созвон с командой", date: Date().addingTimeInterval(300),
                                         minutesBefore: 5, source: .calendar, link: URL(string: "https://meet.google.com/abc"))); shot("10-reminder-calendar")
        model.event = nil
        model.batteries.debugSet(devices: [
            DeviceBattery(name: "AirPods Pro", symbol: "airpodspro", levels: [
                .init(label: "Левый", symbol: "airpod.left", percent: 100),
                .init(label: "Правый", symbol: "airpod.right", percent: 18),
                .init(label: "Кейс", symbol: "airpodspro.chargingcase.wireless.fill", percent: 64, charging: true)],
                isConnected: false),
            DeviceBattery(name: "Magic Mouse", symbol: "magicmouse.fill", levels: [.init(label: "", symbol: "", percent: 57)])],
            phone: PhoneBattery(percent: 76, charging: true, updated: Date().addingTimeInterval(-600)),
            mac: BatteryInfo(percent: 82, charging: false))
        model.tasks.debugSet([
            TaskItem(text: "Спортзал", time: "17:00"),
            TaskItem(text: "Немецкий", time: "18:30", notes: "Урок 12: Perfekt\nhttps://www.youtube.com/watch?v=abc\nПовторить слова из прошлого урока"),
            TaskItem(text: "Созвон с командой", time: "22:00"),
            TaskItem(text: "Купить продукты"),
            TaskItem(text: "Сдать эссе", time: "12:00", day: TasksStore.date(forOffset: 1)),
            TaskItem(text: "Ответить на письма", done: true)])
        let tasksHost = NSHostingView(rootView: TasksView(store: model.tasks, gemini: model.gemini)
            .frame(width: 596, height: 118).padding(20).background(Color.black).preferredColorScheme(.dark))
        tasksHost.frame = NSRect(x: 0, y: 0, width: 636, height: 158)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = tasksHost.bitmapImageRepForCachingDisplay(in: tasksHost.bounds) {
            tasksHost.cacheDisplay(in: tasksHost.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("11-tasks.png"))
        }
        SnapshotFlags.openedTask = model.tasks.items[1].id
        let detailHost = NSHostingView(rootView: TasksView(store: model.tasks, gemini: model.gemini)
            .frame(width: 596, height: 118).padding(20).background(Color.black).preferredColorScheme(.dark))
        detailHost.frame = NSRect(x: 0, y: 0, width: 636, height: 158)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = detailHost.bitmapImageRepForCachingDisplay(in: detailHost.bounds) {
            detailHost.cacheDisplay(in: detailHost.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("11-task-detail.png"))
        }
        SnapshotFlags.openedTask = nil
        model.isExpanded = true
        model.expandedContentVisible = true
        let clipHost = NSHostingView(rootView: ClipboardView(clipboard: model.clipboard)
            .frame(width: 596, height: 130).padding(20).background(Color.black).preferredColorScheme(.dark))
        clipHost.frame = NSRect(x: 0, y: 0, width: 636, height: 170)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = clipHost.bitmapImageRepForCachingDisplay(in: clipHost.bounds) {
            clipHost.cacheDisplay(in: clipHost.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("6-clipboard.png"))
        }
        func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
        model.mixer.debugSet(apps: [
            AudioApp(bundleID: "com.apple.Music", name: "Музыка", icon: icon("/System/Applications/Music.app"),
                     processes: [], isPlaying: true),
            AudioApp(bundleID: "com.apple.Safari", name: "Safari", icon: icon("/Applications/Safari.app"),
                     processes: [], isPlaying: true),
            AudioApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram", icon: icon("/Applications/Telegram.app"),
                     processes: [], isPlaying: false)],
            levels: ["com.apple.Safari": 0.35], muted: ["ru.keepcoder.Telegram"], access: .granted)
        model.systemNotifications.debugSet([
            AppNotification(id: "a", bundleID: "ru.keepcoder.Telegram", title: "Мама", subtitle: "",
                            body: "Ты сегодня приедешь?", date: Date()),
            AppNotification(id: "b", bundleID: "com.apple.Passwords", title: "Пароли", subtitle: "",
                            body: "Обнаружен скомпрометированный пароль", date: Date().addingTimeInterval(-3600))])
        for tab in IslandTab.allCases { model.tab = tab; shot("4-\(tab.rawValue)") }
        SnapshotFlags.notesMode = .tasks
        model.tab = .home; model.tab = .notes; shot("4-notes-tasks")
        SnapshotFlags.notesMode = .notes
        SnapshotFlags.batteryPage = 1
        model.tab = .music; model.tab = .home; shot("4-home-airpods")
        SnapshotFlags.batteryPage = 0
        model.tab = .controls
        model.mixer.debugSet(apps: [], levels: [:], muted: [], access: .granted); shot("4-controls-empty")
        model.mixer.debugSet(apps: [], levels: [:], muted: [], access: .denied); shot("4-controls-denied")
        model.media.debugSet(title: "", artist: "", album: "", duration: 0, elapsed: 0, playing: false, artwork: nil, bundleID: nil)
        model.tab = .music; shot("5-empty")
        model.tab = .home; shot("5-home-no-music")
    }
}
