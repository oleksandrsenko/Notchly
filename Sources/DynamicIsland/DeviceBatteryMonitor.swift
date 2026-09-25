import Foundation
import IOBluetooth
import IOKit.ps

struct DeviceBattery: Identifiable, Equatable {
    struct Level: Identifiable, Equatable {
        var id: String { label + symbol }
        var label: String
        var symbol: String
        var percent: Int
        var charging = false
    }

    var id: String { name }
    var name: String
    var symbol: String
    var levels: [Level]
    var isConnected = true

    var isHeadphones: Bool {
        let n = name.lowercased()
        return n.contains("airpods") || n.contains("beats") || symbol.contains("headphones") || symbol.contains("airpods")
    }

    /// Для наушников с кейсом показываем заряд кейса, иначе — минимальный из имеющихся.
    var primaryLevel: Level? {
        levels.first { $0.label == "Кейс" } ?? levels.min { $0.percent < $1.percent }
    }
}

/// Заряд Mac и подключённых Bluetooth-устройств (AirPods, наушники, мышь, клавиатура),
/// а также события «подключили зарядку» и «подключили наушники».
final class DeviceBatteryMonitor: NSObject, ObservableObject {
    @Published private(set) var mac: BatteryInfo?
    @Published private(set) var devices: [DeviceBattery] = []

    /// Наушники для карточки на главной: сначала подключённые, иначе последний известный заряд.
    var headphones: DeviceBattery? {
        let all = devices.filter(\.isHeadphones)
        return all.first(where: \.isConnected) ?? all.first
    }

    /// Мышь, клавиатура, трекпад и прочие подключённые Bluetooth-устройства с зарядом.
    var accessories: [DeviceBattery] {
        devices.filter { !$0.isHeadphones && $0.isConnected }
    }

    /// Заряд iPhone из файла, который пишет автоматизация «Команд» (см. PhoneBattery).
    @Published private(set) var phone: PhoneBattery?

    var onChargerConnected: ((BatteryInfo) -> Void)?
    var onAudioDeviceConnected: ((DeviceBattery) -> Void)?

    private var timer: Timer?
    private var loading = false
    private var wasOnAC: Bool?
    private var connectNotification: IOBluetoothUserNotification?
    private let startedAt = Date()

    override init() {
        super.init()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        startPowerNotifications()
        // Без описания доступа в Info.plist (запуск вне .app) macOS аварийно завершит процесс.
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil {
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(deviceConnected(_:fromDevice:)))
        }
    }

    /// Для снапшотов.
    func debugSet(devices: [DeviceBattery], phone: PhoneBattery?) {
        timer?.invalidate()
        loading = true
        self.devices = devices
        self.phone = phone
    }

    func refresh(completion: (() -> Void)? = nil) {
        mac = BatteryInfo.read()
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = Self.readBluetooth()
            let phone = PhoneBattery.read()
            DispatchQueue.main.async {
                self?.loading = false
                if self?.devices != devices { self?.devices = devices }
                if self?.phone != phone { self?.phone = phone }
                completion?()
            }
        }
    }

    // MARK: - Зарядка

    private func startPowerNotifications() {
        wasOnAC = BatteryInfo.read()?.onAC
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<DeviceBatteryMonitor>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func powerChanged() {
        guard let info = BatteryInfo.read() else { return }
        mac = info
        if info.onAC && wasOnAC == false { onChargerConnected?(info) }
        wasOnAC = info.onAC
    }

    // MARK: - Наушники

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        // При запуске система сообщает обо всех уже подключённых устройствах — их пропускаем.
        guard Date().timeIntervalSince(startedAt) > 5 else { return }
        guard device.deviceClassMajor == kBluetoothDeviceClassMajorAudio else { return }
        let name = device.name ?? "Наушники"
        // Заряд появляется в системе не сразу после подключения.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh {
                guard let self else { return }
                let device = self.devices.first { $0.name == name && $0.isConnected }
                    ?? DeviceBattery(name: name, symbol: Self.symbol(for: name, info: ["device_minorType": "Headphones"]),
                                     levels: [])
                self.onAudioDeviceConnected?(device)
            }
        }
    }

    private static func readBluetooth() -> [DeviceBattery] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var result: [DeviceBattery] = []
        for controller in controllers {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in controller[key] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        let levels = parseLevels(info, name: name)
                        guard !levels.isEmpty else { continue }
                        result.append(DeviceBattery(name: name, symbol: symbol(for: name, info: info),
                                                    levels: levels, isConnected: connected))
                    }
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private static func parseLevels(_ info: [String: Any], name: String) -> [DeviceBattery.Level] {
        let isPro = name.localizedCaseInsensitiveContains("pro")
        let order: [(key: String, label: String, symbol: String)] = [
            ("device_batteryLevelLeft", "Левый", "airpod.left"),
            ("device_batteryLevelRight", "Правый", "airpod.right"),
            ("device_batteryLevelCase", "Кейс", isPro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"),
            ("device_batteryLevelMain", "", ""),
            ("device_batteryLevel", "", ""),
        ]
        return order.compactMap { item in
            guard let raw = info[item.key] as? String,
                  let percent = Int(raw.filter(\.isNumber)) else { return nil }
            return DeviceBattery.Level(label: item.label, symbol: item.symbol, percent: percent)
        }
    }

    static func symbol(for name: String, info: [String: Any]) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("magic mouse") { return "magicmouse.fill" }
        if lower.contains("magic keyboard") { return "keyboard.fill" }
        if lower.contains("magic trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        switch info["device_minorType"] as? String {
        case "Headphones", "Headset": return "headphones"
        case "Keyboard": return "keyboard"
        case "Mouse": return "magicmouse.fill"
        case "Trackpad": return "rectangle.and.hand.point.up.left"
        case "Speaker": return "hifispeaker"
        case "Gamepad": return "gamecontroller"
        default: return "wave.3.right"
        }
    }
}

/// Заряд iPhone. На Mac нет API, чтобы его узнать, поэтому автоматизация в «Командах» на iPhone
/// сохраняет файл «iphone-battery.txt» в iCloud Drive (папка «Shortcuts» или «DynamicIsland»),
/// например с текстом «85 Да» — процент и заряжается ли телефон.
struct PhoneBattery: Equatable {
    var percent: Int
    var charging: Bool
    var updated: Date

    static let fileName = "iphone-battery.txt"

    static var candidates: [URL] {
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents")
        return [docs.appendingPathComponent("iCloud~is~workflow~my~workflows/Documents"),
                docs.appendingPathComponent("com~apple~CloudDocs/DynamicIsland"),
                docs.appendingPathComponent("com~apple~CloudDocs/Shortcuts")]
            .map { $0.appendingPathComponent(fileName) }
    }

    static func read() -> PhoneBattery? {
        let fm = FileManager.default
        var best: PhoneBattery?
        for url in candidates {
            // Файл мог быть выгружен из iCloud — просим скачать, прочитаем в следующий раз.
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(fileName).icloud")
            if fm.fileExists(atPath: placeholder.path) { try? fm.startDownloadingUbiquitousItem(at: url) }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  // Старше суток — уже неправда.
                  Date().timeIntervalSince(date) < 86_400 else { continue }
            let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard let value = numbers.first else { continue }
            // Команды отдают уровень либо 0…100, либо 0…1.
            let percent = value <= 1 && text.contains(".") ? Int((Double(text.filter { $0.isNumber || $0 == "." }) ?? 0) * 100) : value
            let lower = text.lowercased()
            let charging = ["да", "yes", "true", "заряж", "charging"].contains { lower.contains($0) }
            let item = PhoneBattery(percent: min(max(percent, 0), 100), charging: charging, updated: date)
            if best == nil || date > best!.updated { best = item }
        }
        return best
    }
}
