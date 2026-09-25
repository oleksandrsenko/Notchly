import SwiftUI

struct MusicPlayerView: View {
    @ObservedObject var media: MediaController

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
                    .frame(width: 128, height: 128)
                    .background {
                        // Свечение из самой обложки: каждый край светит своим цветом и плавно гаснет.
                        if let glow = media.glow {
                            let side = 128 * (1 + ArtworkColor.glowSpread * 2)
                            Image(nsImage: glow)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: side, height: side)
                                .opacity(media.isPlaying ? 1 : 0.35)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
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
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .id(media.trackID)
                    .transition(.asymmetric(
                        insertion: .offset(y: 14).combined(with: .blurFade),
                        removal: .offset(y: -14).combined(with: .blurFade)))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    EqualizerView(isPlaying: media.isPlaying, color: .white, bars: 5)
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
                .overlay(alignment: .trailing) {
                    // Незаметная кнопка повтора трека.
                    IconButton(systemName: "repeat.1", size: 12, padding: 6) { media.toggleRepeat() }
                        .foregroundStyle(.white)
                        .opacity(media.repeatOne ? 0.95 : 0.35)
                        .help(media.repeatOne ? "Повтор трека включён" : "Повторять этот трек")
                }
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
                            .fill(Color.white)
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
        .padding(.vertical, 2)
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

    var body: some View {
        Button { service.open() } label: {
            VStack(spacing: 5) {
                ServiceLogo(name: service.name, hovering: hovering)
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(hovering ? 1.06 : 1)
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
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h } }
    }
}

/// Логотипы сервисов: минималистичные белые знаки на полупрозрачном скруглённом квадрате, векторные.
struct ServiceLogo: View {
    var name: String
    var hovering = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.26, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.16 : 0.08))
                glyph(s).foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func glyph(_ s: CGFloat) -> some View {
        switch name {
        case "Spotify":
            // Три дуги Spotify.
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let half = [0.25, 0.21, 0.17][i], y = [0.38, 0.51, 0.63][i], top = [0.28, 0.43, 0.56][i]
                    Path { p in
                        p.move(to: CGPoint(x: (0.5 - half) * s, y: y * s))
                        p.addQuadCurve(to: CGPoint(x: (0.5 + half) * s, y: (y + 0.04) * s),
                                       control: CGPoint(x: 0.5 * s, y: top * s))
                    }
                    .stroke(style: StrokeStyle(lineWidth: [0.07, 0.06, 0.05][i] * s, lineCap: .round))
                }
            }
        case "YouTube Music":
            ZStack {
                Circle().stroke(lineWidth: s * 0.05).frame(width: s * 0.5, height: s * 0.5)
                Path { p in
                    p.move(to: CGPoint(x: 0.44 * s, y: 0.39 * s))
                    p.addLine(to: CGPoint(x: 0.62 * s, y: 0.5 * s))
                    p.addLine(to: CGPoint(x: 0.44 * s, y: 0.61 * s))
                    p.closeSubpath()
                }
            }
        default:
            // Двойная нота Apple Music.
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0.41 * s, y: 0.64 * s))
                    p.addLine(to: CGPoint(x: 0.41 * s, y: 0.32 * s))
                    p.addLine(to: CGPoint(x: 0.67 * s, y: 0.27 * s))
                    p.addLine(to: CGPoint(x: 0.67 * s, y: 0.59 * s))
                }
                .stroke(style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round, lineJoin: .round))
                Ellipse().frame(width: s * 0.15, height: s * 0.115).rotationEffect(.degrees(-18))
                    .position(x: 0.35 * s, y: 0.655 * s)
                Ellipse().frame(width: s * 0.15, height: s * 0.115).rotationEffect(.degrees(-18))
                    .position(x: 0.61 * s, y: 0.605 * s)
            }
        }
    }
}
