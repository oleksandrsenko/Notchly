import Foundation
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
}

/// Заряд Mac и подключённых Bluetooth-устройств (AirPods, наушники, мышь, клавиатура).
final class DeviceBatteryMonitor: ObservableObject {
    @Published private(set) var mac: BatteryInfo?
    @Published private(set) var devices: [DeviceBattery] = []

    private var timer: Timer?
    private var loading = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        mac = BatteryInfo.read()
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = Self.readBluetooth()
            DispatchQueue.main.async {
                self?.loading = false
                if self?.devices != devices { self?.devices = devices }
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
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let levels = parseLevels(info, name: name)
                    guard !levels.isEmpty else { continue }
                    result.append(DeviceBattery(name: name, symbol: symbol(for: name, info: info), levels: levels))
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

    private static func symbol(for name: String, info: [String: Any]) -> String {
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
