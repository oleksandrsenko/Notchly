import AppKit
import SwiftUI

/// Окно настроек открывается отдельно, прямо под островом. Пока оно открыто, остров стоит раскрытым,
/// и каждое изменение сразу видно на нём.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var model: IslandModel?

    func show(model: IslandModel) {
        self.model = model
        model.settingsOpen = true
        model.expand(to: model.isExpanded ? nil : .controls)
        if window == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470),
                                        styleMask: [.titled, .closable, .miniaturizable],
                                        backing: .buffered, defer: false)
            window.title = "Настройки Notchly"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.setContentSize(NSSize(width: 660, height: 470))
            self.window = window
        }
        guard let window else { return }
        place(window, model: model)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Под раскрытым островом, по центру того же экрана.
    private func place(_ window: NSWindow, model: IslandModel) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        // Ниже всей прозрачной панели острова, а не только его видимой формы.
        let panelBottom = screen.frame.maxY - IslandMetrics.windowSize.height
        let size = window.frame.size
        var origin = NSPoint(x: screen.frame.midX - size.width / 2, y: panelBottom - 12 - size.height)
        origin.y = max(origin.y, screen.visibleFrame.minY + 8)
        window.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        model.settingsOpen = false
        model.collapse()
    }
}

/// У приложения без меню ⌘W сам не работает — закрываем окно по физической клавише.
private final class SettingsWindow: NSWindow {
    /// Esc закрывает окно, как лист настроек.
    override func cancelOperation(_ sender: Any?) { performClose(nil) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, flags == [.command] {
            switch event.keyCode {
            case 13: performClose(nil); return true                                        // W
            case 8: if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case 9: if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Содержимое

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "Основные", tabs = "Вкладки", island = "Остров", notifications = "Уведомления",
             clipboard = "Буфер обмена", about = "О Notchly"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .tabs: return "rectangle.3.group.fill"
            case .island: return "capsule.fill"
            case .notifications: return "bell.badge.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .about: return "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general: return .gray
            case .tabs: return .blue
            case .island: return .indigo
            case .notifications: return .red
            case .clipboard: return .orange
            case .about: return .teal
            }
        }
    }

    var model: IslandModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var shots: ScreenshotStore
    @ViewState private var section: Pane? = SnapshotFlags.settingsPane

    init(model: IslandModel) {
        self.model = model
        settings = model.settings
        clipboard = model.clipboard
        shots = model.clipboard.shots
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $section) { item in
                Label {
                    Text(item.rawValue)
                } icon: {
                    Image(systemName: item.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(item.tint.gradient))
                }
                .tag(item)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch section ?? .general {
                case .general: general
                case .tabs: tabs
                case .island: island
                case .notifications: notifications
                case .clipboard: clipboardPane
                case .about: about
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
        .onChange(of: section) { _, value in
            // Остров показывает то, что сейчас настраивается.
            switch value {
            case .clipboard: showTab(.clipboard)
            case .tabs, .general: break
            default: showTab(.home)
            }
        }
    }

    private func showTab(_ tab: IslandTab) {
        guard settings.isVisible(tab) else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) { model.tab = tab }
    }

    // MARK: Основные

    private var general: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle("Значок в строке меню", isOn: $settings.menuBarIcon)
            } footer: {
                if !settings.menuBarIcon {
                    Text("Без значка настройки открываются из вкладки «Управление» или повторным запуском Notchly.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section {
                Picker("Открывать на вкладке", selection: $settings.openOnHome) {
                    Text("Главная").tag(true)
                    Text("Последняя открытая").tag(false)
                }
                LabeledContent("Закрывать, когда курсор ушёл, через") {
                    Text("\(settings.closeDelay.formatted(.number.precision(.fractionLength(1)))) с")
                        .monospacedDigit()
                }
                Slider(value: Binding(get: { settings.closeDelay },
                                      set: { settings.closeDelay = ($0 * 10).rounded() / 10 }),
                       in: AppSettings.closeDelayRange) {
                    Text("Задержка")
                } minimumValueLabel: {
                    Image(systemName: "hare")
                } maximumValueLabel: {
                    Image(systemName: "tortoise")
                }
                .labelsHidden()
            } header: {
                Text("Раскрытый остров")
            } footer: {
                Text("Клик мимо острова закрывает его сразу.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Вкладки

    private var tabs: some View {
        Form {
            ForEach([TabSlot.Side.leading, .trailing], id: \.self) { side in
                Section {
                    let slots = settings.tabs.filter { $0.side == side }
                    ForEach(slots) { slot in
                        TabSlotRow(slot: slot,
                                   isFirst: slot.tab == slots.first?.tab,
                                   isLast: slot.tab == slots.last?.tab,
                                   move: { moveTab(slot, by: $0) },
                                   switchSide: { switchSide(slot) },
                                   setVisible: { setVisible(slot, $0) })
                    }
                    if slots.isEmpty {
                        Text("Пусто").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(side == .leading ? "Слева от выреза" : "Справа от выреза")
                } footer: {
                    if side == .trailing {
                        HStack(alignment: .top) {
                            Text("Колокольчик уведомлений всегда стоит справа, последним. Главная всегда видна.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Button("Как было") { animateTabs { settings.resetTabs() } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func animateTabs(_ change: () -> Void) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { change() }
    }

    /// Сдвиг внутри своей стороны: меняемся местами с соседом по этой же стороне.
    private func moveTab(_ slot: TabSlot, by delta: Int) {
        var all = settings.tabs
        let sameSide = all.indices.filter { all[$0].side == slot.side }
        guard let pos = sameSide.firstIndex(where: { all[$0].tab == slot.tab }),
              sameSide.indices.contains(pos + delta) else { return }
        all.swapAt(sameSide[pos], sameSide[pos + delta])
        animateTabs { settings.tabs = all }
    }

    /// На другую сторону — в её конец.
    private func switchSide(_ slot: TabSlot) {
        var all = settings.tabs
        all.removeAll { $0.tab == slot.tab }
        var moved = slot
        moved.side = slot.side == .leading ? .trailing : .leading
        all.append(moved)
        animateTabs { settings.tabs = all }
    }

    private func setVisible(_ slot: TabSlot, _ visible: Bool) {
        var all = settings.tabs
        guard let i = all.firstIndex(where: { $0.tab == slot.tab }) else { return }
        all[i].visible = visible
        animateTabs { settings.tabs = all }
    }

    // MARK: Остров

    private var island: some View {
        Form {
            Section("Свёрнутый остров") {
                Toggle("Музыка: обложка и эквалайзер по бокам выреза", isOn: $settings.musicActivity)
                Toggle("Шторка с названием нового трека", isOn: $settings.trackPeek)
                Toggle("Громкость и яркость вместо системного индикатора", isOn: $settings.hud)
                Toggle("«Скопировано» при копировании", isOn: $settings.copiedPeek)
            }
            Section("Карточки") {
                Toggle("Подключили зарядку", isOn: $settings.chargingCard)
                Toggle("Подключили наушники (заряд AirPods)", isOn: $settings.headphonesCard)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Уведомления

    private var notifications: some View {
        Form {
            Section {
                Toggle("Уведомления приложений", isOn: $settings.appNotifications)
                Toggle("Новые письма Gmail", isOn: $settings.gmailNotifications)
                Toggle("Напоминания о задачах и встречах", isOn: $settings.reminders)
            } header: {
                Text("Показывать на острове")
            } footer: {
                Text("Всё пришедшее остаётся в центре уведомлений (колокольчик) — выключается только всплывающая карточка. Во время «Помидора» уведомления копятся молча.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Тихий сигнал: напоминания, таймер, будильник", isOn: $settings.sounds)
                Button("Прослушать") { SoftChime.play() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Буфер обмена

    @ViewState private var confirmHistory = false
    @ViewState private var confirmShots = false

    private var clipboardPane: some View {
        Form {
            Section("Текст") {
                Toggle("Запоминать скопированный текст", isOn: $settings.clipboardHistory)
                Picker("Хранить историю", selection: Binding(
                    get: { clipboard.retentionDays }, set: { clipboard.retentionDays = $0 })) {
                    ForEach(ClipboardMonitor.retentionOptions, id: \.self) { days in
                        Text(Self.retentionTitle(days)).tag(days)
                    }
                }
                .disabled(!settings.clipboardHistory)
                Button("Очистить историю…", role: .destructive) { confirmHistory = true }
                    .disabled(clipboard.groups.isEmpty)
                    .confirmationDialog("Очистить всю историю буфера обмена?", isPresented: $confirmHistory) {
                        Button("Очистить", role: .destructive) { clipboard.clear() }
                    }
            }
            Section {
                Toggle("Сохранять снимки экрана и скопированные картинки", isOn: $settings.screenshots)
                Toggle("Брать и снимки, сохранённые на рабочий стол", isOn: $settings.screenshotFiles)
                    .disabled(!settings.screenshots)
                Picker("Хранить снимки", selection: Binding(
                    get: { shots.retentionDays }, set: { shots.retentionDays = $0 })) {
                    ForEach(ScreenshotStore.retentionOptions, id: \.self) { days in
                        Text(Self.retentionTitle(days)).tag(days)
                    }
                }
                .disabled(!settings.screenshots)
                LabeledContent("Занято") {
                    Text("\(shots.items.count) шт. · \(ByteCountFormatter.string(fromByteCount: Int64(shots.totalBytes), countStyle: .file))")
                        .monospacedDigit()
                }
                Button("Удалить все снимки…", role: .destructive) { confirmShots = true }
                    .disabled(shots.items.isEmpty)
                    .confirmationDialog("Удалить все сохранённые снимки?", isPresented: $confirmShots) {
                        Button("Удалить", role: .destructive) { shots.clear() }
                    }
            } header: {
                Text("Снимки")
            } footer: {
                Text("Снимок весит 1–8 МБ, поэтому они хранятся недолго: не больше \(ScreenshotStore.maxItems) штук, старые удаляются сами. Снимки с рабочего стола копируются — оригиналы остаются на месте. Для них macOS один раз спросит доступ к папке.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    static func retentionTitle(_ days: Int) -> String {
        switch days {
        case 0: return "Бесконечно"
        case 1: return "1 день"
        case 2, 3, 4: return "\(days) дня"
        default: return "\(days) дней"
        }
    }

    // MARK: О программе

    private var about: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                    Text("Notchly")
                        .font(.system(size: 22, weight: .bold))
                    Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                    Text("Остров в вырезе экрана: музыка, задачи, таймеры, напоминания и уведомления.\nВсе данные хранятся только на этом Mac.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                Button("Выйти из Notchly") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TabSlotRow: View {
    var slot: TabSlot
    var isFirst: Bool
    var isLast: Bool
    var move: (Int) -> Void
    var switchSide: () -> Void
    var setVisible: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: slot.tab.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Color.black))
                .opacity(slot.visible ? 1 : 0.4)
            Text(slot.tab.title)
                .foregroundStyle(slot.visible ? .primary : .secondary)
            Spacer()
            HStack(spacing: 2) {
                small("chevron.up", help: "Левее / выше", disabled: isFirst) { move(-1) }
                small("chevron.down", help: "Правее / ниже", disabled: isLast) { move(1) }
                small(slot.side == .leading ? "arrow.right" : "arrow.left",
                      help: slot.side == .leading ? "Перенести направо от выреза" : "Перенести налево от выреза",
                      disabled: false, action: switchSide)
            }
            Toggle("", isOn: Binding(get: { slot.visible }, set: setVisible))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(slot.tab == .home)
                .help(slot.tab == .home ? "Главная всегда видна" : "Показывать вкладку")
        }
    }

    private func small(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }
}
