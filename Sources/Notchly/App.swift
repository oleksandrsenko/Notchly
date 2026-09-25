import AppKit
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?

    static func main() {
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notchly")
        let menu = NSMenu()

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let retention = NSMenuItem(title: "Хранить буфер обмена", action: nil, keyEquivalent: "")
        let retentionMenu = NSMenu()
        for days in ClipboardMonitor.retentionOptions {
            let title = days == 0 ? "Бесконечно" : days == 1 ? "1 день" : "\(days) дней"
            let item = NSMenuItem(title: title, action: #selector(setClipboardRetention(_:)), keyEquivalent: "")
            item.target = self
            item.tag = days
            retentionMenu.addItem(item)
        }
        retentionMenu.delegate = self
        retention.submenu = retentionMenu
        menu.addItem(retention)

        let clear = NSMenuItem(title: "Очистить файлы", action: #selector(clearShelf), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func setClipboardRetention(_ sender: NSMenuItem) {
        controller?.model.clipboard.retentionDays = sender.tag
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = controller?.model.clipboard.retentionDays ?? 7
        for item in menu.items { item.state = item.tag == current ? .on : .off }
    }

    @objc private func clearShelf() {
        controller?.model.shelf.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
    }
}
