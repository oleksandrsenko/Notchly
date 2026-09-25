import SwiftUI

/// Свёрнутый остров во время воспроизведения: обложка слева от выреза, эквалайзер справа.
/// После смены трека на пару секунд опускается «шторка» с названием.
struct CompactMusicView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var model: IslandModel
    var ns: Namespace.ID

    var body: some View {
        let h = model.notchSize.height
        let art = min(h - 10, 26)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 6)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .frame(width: art, height: art)
                Spacer(minLength: model.notchSize.width)
                EqualizerView(isPlaying: media.isPlaying, color: media.accent)
                    .frame(width: 18, height: 13)
                    .padding(.trailing, 3)
            }
            .padding(.horizontal, 9)
            .frame(height: h)

            if model.peek && media.hasTrack {
                HStack(spacing: 6) {
                    Text(media.title)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    if !media.artist.isEmpty {
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Text(media.artist).foregroundStyle(media.accent.opacity(0.9))
                    }
                }
                .font(.system(size: 12.5))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(height: IslandMetrics.peekExtraHeight - 6)
                .id(media.trackID)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity))
            }
        }
    }
}

/// Индикатор громкости или яркости по бокам от выреза.
struct HUDView: View {
    var state: HUDState
    var notchWidth: CGFloat

    private var icon: String {
        switch state.kind {
        case .brightness:
            return state.value < 0.33 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if state.muted || state.value < 0.01 { return "speaker.slash.fill" }
            if state.value < 0.33 { return "speaker.wave.1.fill" }
            if state.value < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        let shown = state.muted ? 0 : CGFloat(state.value)
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: state.value)
                .frame(width: 26)
                .padding(.leading, 14)
            Spacer(minLength: notchWidth)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.gradient)
                    .frame(width: 48 * shown)
            }
            .frame(width: 48, height: 5)
            .padding(.trailing, 14)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shown)
        }
        .frame(maxHeight: .infinity)
    }
}

/// «Скопировано из …»: иконка приложения слева от выреза, значок буфера справа.
struct ClipPeekView: View {
    var group: ClipGroup
    var icon: NSImage
    var notchWidth: CGFloat
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .scaleEffect(appeared ? 1 : 0.4)
                .padding(.leading, 16)
            Spacer(minLength: notchWidth)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
                .scaleEffect(appeared ? 1 : 0.4)
                .padding(.trailing, 18)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.05)) { appeared = true }
        }
    }
}
