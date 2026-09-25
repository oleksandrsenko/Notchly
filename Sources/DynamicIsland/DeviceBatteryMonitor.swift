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

    func refresh(completion: (() -> Void)? = nil) {
        mac = BatteryInfo.read()
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = Self.readBluetooth()
            DispatchQueue.main.async {
                self?.loading = false
                if self?.devices != devices { self?.devices = devices }
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
        switch info["device_minorType"] as? String {
        case "Headphones", "Headset": return "headphones"
        case "Keyboard": return "keyboard"
        case "Mouse": return "magicmouse"
        case "Trackpad": return "rectangle.and.hand.point.up.left"
        case "Speaker": return "hifispeaker"
        case "Gamepad": return "gamecontroller"
        default: return "wave.3.right"
        }
    }
}
