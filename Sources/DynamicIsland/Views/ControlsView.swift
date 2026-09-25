import SwiftUI

struct ControlsView: View {
    @ObservedObject var volume: VolumeController
    @ObservedObject var brightness: BrightnessController

    private var volumeIcon: String {
        if volume.isMuted || volume.volume < 0.01 { return "speaker.slash.fill" }
        if volume.volume < 0.33 { return "speaker.wave.1.fill" }
        if volume.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        VStack(spacing: 14) {
            row(title: "Громкость", available: volume.isAvailable,
                hint: "Устройство вывода не поддерживает регулировку") {
                CapsuleSlider(value: volume.isMuted ? 0 : Double(volume.volume),
                              icon: volumeIcon,
                              iconAction: { volume.toggleMute() },
                              onChange: { volume.set(Float($0)) })
            }
            row(title: "Яркость", available: brightness.isAvailable,
                hint: "Недоступно для этого дисплея") {
                CapsuleSlider(value: Double(brightness.brightness),
                              icon: brightness.brightness < 0.33 ? "sun.min.fill" : "sun.max.fill",
                              onChange: { brightness.set(Float($0)) })
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    @ViewBuilder
    private func row<Content: View>(title: String, available: Bool, hint: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 4)
            if available {
                content()
            } else {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(.white.opacity(0.06)))
            }
        }
    }
}
