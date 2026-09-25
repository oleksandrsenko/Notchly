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
        if CommandLine.arguments.contains("--imap-selftest") {
            GmailSelfTest.run()
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
        controller = NotchWindowController()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")
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
