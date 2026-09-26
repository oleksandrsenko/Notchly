import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var menuBarObserver: AnyCancellable?
    private var languageObserver: AnyCancellable?

    static func main() {
        // --lang en: снапшоты на английском (для README).
        if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count,
           let language = AppLanguage(rawValue: CommandLine.arguments[i + 1]) {
            Loc.language = language
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated {
                Snapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--chime") {
            print("Сигнал напоминания: \(SoftChime.isAvailable ? "OK" : "не собрался")")
            SoftChime.play()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            exit(0)
        }
        if CommandLine.arguments.contains("--reminders-selftest") {
            let tasks = TasksStore(persistent: false)
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            tasks.add("Через 10 минут", time: f.string(from: Date().addingTimeInterval(10 * 60)))
            tasks.add("Через 5 минут", time: f.string(from: Date().addingTimeInterval(5 * 60)))
            tasks.add("Через 30 минут", time: f.string(from: Date().addingTimeInterval(30 * 60)))
            tasks.add("Прямо сейчас", time: f.string(from: Date()))
            let center = ReminderCenter(tasks: tasks)
            var fired: [String] = []
            center.onFire = { fired.append("\($0.title) — за \($0.minutesBefore) мин") }
            center.start()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            print(fired.isEmpty ? "Ничего не сработало" : fired.joined(separator: "\n"))
            exit(0)
        }
        if CommandLine.arguments.contains("--imap-selftest") {
            GmailSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--notifications-selftest") {
            let report = SystemNotificationsReader().selfTestReport()
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/notifications-selftest.txt")
            try? report.write(to: url, atomically: true, encoding: .utf8)
            print(report)
            exit(0)
        }
        if CommandLine.arguments.contains("--services-selftest") {
            var lines: [String] = []
            let group = DispatchGroup()
            group.enter()
            GeminiAssistant.selfTest { lines.append("Gemini: " + $0); group.leave() }
            group.enter()
            GmailClient.selfTest { lines.append("Gmail: " + $0); group.leave() }
            while group.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/services-selftest.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exit(0)
        }
        if CommandLine.arguments.contains("--batteries-selftest") {
            let monitor = DeviceBatteryMonitor()
            RunLoop.main.run(until: Date().addingTimeInterval(4))
            for d in monitor.devices {
                print(d.name, d.isConnected ? "подключено" : "не подключено", d.levels.map { "\($0.label) \($0.percent)%" })
            }
            print("Аксессуары на главной:", monitor.accessories.map(\.name))
            var report = monitor.devices.map { d in
                "\(d.name) \(d.isConnected ? "подключено" : "не подключено") " + d.levels.map { "\($0.label) \($0.percent)%" }.joined(separator: ", ")
            }
            report.append("IOBluetooth: " + DeviceBatteryMonitor.bluetoothLevels()
                .map { "\($0.key): " + $0.value.map { "\($0.label) \($0.percent)%" }.joined(separator: ", ") }
                .joined(separator: " | "))
            report.append("Источники питания: " + DeviceBatteryMonitor.accessoryLevels()
                .map { "\($0.key) \($0.value.percent)%" }.sorted().joined(separator: ", "))
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/batteries-selftest.txt")
            try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exit(0)
        }
        if CommandLine.arguments.contains("--mixer-selftest") {
            let mixer = AppAudioMixer()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            print("Доступ к записи аудио: \(mixer.access)")
            for app in mixer.apps {
                print("\(app.name) [\(app.bundleID)] процессы: \(app.processes) играет: \(app.isPlaying)")
            }
            if mixer.apps.isEmpty { print("Звук сейчас никто не выводит") }
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.run()
        controller = NotchWindowController()
        setupStatusItem()
    }

    /// Повторный запуск (например, из Finder), когда значок в строке меню спрятан, — открывает настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func openSettings() {
        guard let model = controller?.model else { return }
        SettingsWindowController.shared.show(model: model)
    }

    /// Все настройки живут в отдельном окне; в строке меню — только вход в него и выход.
    private func setupStatusItem() {
        guard let model = controller?.model else { return }
        updateStatusItem(visible: model.settings.menuBarIcon)
        menuBarObserver = model.settings.$menuBarIcon
            .removeDuplicates()
            .sink { [weak self] visible in DispatchQueue.main.async { self?.updateStatusItem(visible: visible) } }
        // Пункты меню пересоздаём на новом языке.
        languageObserver = model.settings.$language
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let model = self.controller?.model else { return }
                    self.updateStatusItem(visible: false)
                    self.updateStatusItem(visible: model.settings.menuBarIcon)
                }
            }
    }

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notchly")
        let menu = NSMenu()
        let settings = NSMenuItem(title: L("Настройки…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Выйти из Notchly"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
    }
}
