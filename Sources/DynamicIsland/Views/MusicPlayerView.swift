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

            ServiceColumn()
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

/// Музыкальный сервис: открывает приложение, если оно установлено, иначе сайт.
struct MusicService: Identifiable {
    var id: String { name }
    var name: String
    var bundleIDs: [String]
    /// Bundle id iOS-версии: по нему иконка подтягивается из App Store, если приложения нет на Mac.
    var storeBundleID: String?
    var web: URL
    var fallbackSymbol: String

    static let all = [
        MusicService(name: "Apple Music", bundleIDs: ["com.apple.Music"], storeBundleID: nil,
                     web: URL(string: "https://music.apple.com")!, fallbackSymbol: "music.note"),
        MusicService(name: "Spotify", bundleIDs: ["com.spotify.client"], storeBundleID: "com.spotify.client",
                     web: URL(string: "https://open.spotify.com")!, fallbackSymbol: "dot.radiowaves.left.and.right"),
        MusicService(name: "YouTube Music", bundleIDs: ["com.github.th-ch.youtube-music", "com.github.th-ch.pear-desktop"],
                     storeBundleID: "com.google.ios.youtubemusic",
                     web: URL(string: "https://music.youtube.com")!, fallbackSymbol: "play.rectangle.fill"),
    ]

    var appURL: URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    var localIcon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    func open() {
        if let appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else {
            NSWorkspace.shared.open(web)
        }
    }
}

/// Колонка быстрых ссылок справа от плеера.
private struct ServiceColumn: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(MusicService.all) { service in
                ServiceButton(service: service, iconSize: 26, showsName: false)
                    .help(service.appURL == nil ? "Открыть \(service.name) в браузере" : "Открыть \(service.name)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}

/// Когда ничего не играет — быстрые кнопки запуска любимых сервисов.
private struct EmptyPlayerView: View {
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
                ForEach(MusicService.all) { service in
                    ServiceButton(service: service, iconSize: 38, showsName: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ServiceButton: View {
    var service: MusicService
    var iconSize: CGFloat
    var showsName: Bool
    @ViewState private var hovering = false
    @ViewState private var remoteIcon: NSImage?

    var body: some View {
        Button { service.open() } label: {
            VStack(spacing: 5) {
                Group {
                    if let icon = service.localIcon {
                        Image(nsImage: icon).resizable()
                    } else if let remoteIcon {
                        Image(nsImage: remoteIcon)
                            .resizable()
                            .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous))
                            .padding(iconSize * 0.05)
                            .transition(.blurFade)
                    } else {
                        Image(systemName: service.fallbackSymbol)
                            .font(.system(size: iconSize * 0.42, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: iconSize * 0.24).fill(.white.opacity(0.12)))
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(hovering ? 1.12 : 1)
                .onAppear {
                    guard service.localIcon == nil, let id = service.storeBundleID else { return }
                    RemoteImages.appIcon(bundleID: id) { image in
                        withAnimation(.smooth(duration: 0.4)) { remoteIcon = image }
                    }
                }
                if showsName {
                    Text(service.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: showsName ? 90 : iconSize)
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hovering = h } }
    }
}
