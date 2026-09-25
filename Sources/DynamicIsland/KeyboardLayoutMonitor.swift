import AppKit
import Carbon

/// Текущая раскладка клавиатуры («RU», «EN»…), обновляется при переключении.
final class KeyboardLayoutMonitor: ObservableObject {
    @Published private(set) var code = ""

    init() {
        update()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in self?.update() }
    }

    private func update() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return }
        let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]
        let value = String((languages?.first ?? "").prefix(2)).uppercased()
        if value != code { code = value }
    }
}
