import SwiftUI

struct MusicPlayerView: View {
    @ObservedObject var media: MediaController
    var ns: Namespace.ID

    var body: some View {
        if media.hasTrack {
            player
        } else {
            EmptyPlayerView()
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var player: some View {
        HStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 16)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .frame(width: 128, height: 128)
                    .background {
                        // Свечение цвета обложки.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(media.accent)
                            .blur(radius: 18)
                            .opacity(media.isPlaying ? 0.5 : 0.15)
                            .offset(y: 4)
                    }
                    .scaleEffect(media.isPlaying ? 1 : 0.9)
                    .animation(.spring(response: 0.55, dampingFraction: 0.7), value: media.isPlaying)
                    .onTapGesture { media.openSourceApp() }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(media.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(media.artist.isEmpty ? media.album : media.artist)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(media.accent.opacity(0.9))
                    }
                    .lineLimit(1)
                    .id(media.trackID)
                    .transition(.asymmetric(
                        insertion: .offset(y: 14).combined(with: .blurFade),
                        removal: .offset(y: -14).combined(with: .blurFade)))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    EqualizerView(isPlaying: media.isPlaying, color: media.accent, bars: 5)
                        .frame(width: 26, height: 20)
                        .padding(.top, 4)
                }
                .clipped()

                Spacer(minLength: 8)
                ProgressSection(media: media)
                Spacer(minLength: 6)

                HStack(spacing: 22) {
                    IconButton(systemName: "backward.fill", size: 19) { media.previous() }
                    IconButton(systemName: media.isPlaying ? "pause.fill" : "play.fill", size: 26, padding: 8) {
                        media.togglePlayPause()
                    }
                    IconButton(systemName: "forward.fill", size: 19) { media.next() }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ProgressSection: View {
    @ObservedObject var media: MediaController
    @ViewState private var scrub: Double?
    @ViewState private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = max(media.duration, 0.01)
            let position = scrub ?? media.position(at: ctx.date)
            let fraction = media.duration > 0 ? min(position / duration, 1) : 0
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(media.accent.gradient)
                            .frame(width: geo.size.width * fraction)
                            .animation(scrub == nil ? .linear(duration: 0.5) : nil, value: fraction)
                    }
                    .frame(height: hovering || scrub != nil ? 8 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard media.duration > 0 else { return }
                            scrub = min(max(g.location.x / geo.size.width, 0), 1) * media.duration
                        }
                        .onEnded { _ in
                            if let scrub { media.seek(to: scrub) }
                            scrub = nil
                        })
                    .onHover { h in withAnimation(.spring(response: 0.25)) { hovering = h } }
                }
                .frame(height: 12)

                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text(media.duration > 0 ? "-" + formatTime(max(media.duration - position, 0)) : "")
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Когда ничего не играет — быстрые кнопки запуска любимых сервисов.
private struct EmptyPlayerView: View {
    private struct Service: Identifiable {
        var id: String { name }
        var name: String
        var bundleIDs: [String]
        var web: URL?
        var fallbackSymbol: String
    }

    private let services = [
        Service(name: "Apple Music", bundleIDs: ["com.apple.Music"], web: nil, fallbackSymbol: "music.note"),
        Service(name: "Spotify", bundleIDs: ["com.spotify.client"],
                web: URL(string: "https://open.spotify.com"), fallbackSymbol: "dot.radiowaves.left.and.right"),
        Service(name: "Яндекс Музыка", bundleIDs: ["ru.yandex.desktop.music", "ru.yandex.music"],
                web: URL(string: "https://music.yandex.ru"), fallbackSymbol: "headphones"),
        Service(name: "YouTube Music", bundleIDs: ["com.github.th-ch.youtube-music", "com.github.th-ch.pear-desktop"],
                web: URL(string: "https://music.youtube.com"), fallbackSymbol: "play.rectangle.fill"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("Сейчас ничего не играет")
                    .font(.system(size: 15, weight: .semibold))
                Text("Включите музыку — обложка и управление появятся здесь")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 12) {
                ForEach(services) { service in
                    ServiceButton(name: service.name, icon: icon(for: service), symbol: service.fallbackSymbol) {
                        open(service)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appURL(for service: Service) -> URL? {
        service.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    private func icon(for service: Service) -> NSImage? {
        appURL(for: service).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func open(_ service: Service) {
        if let url = appURL(for: service) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let web = service.web {
            NSWorkspace.shared.open(web)
        }
    }
}

private struct ServiceButton: View {
    var name: String
    var icon: NSImage?
    var symbol: String
    var action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.12)))
                    }
                }
                .frame(width: 38, height: 38)
                .scaleEffect(hovering ? 1.1 : 1)
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                    .lineLimit(1)
            }
            .frame(width: 90)
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hovering = h } }
    }
}
