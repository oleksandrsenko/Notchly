import SwiftUI

/// Главная: часы, дата, мини-плеер, погода и заряд MacBook / наушников.
struct HomeView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @ObservedObject var batteries: DeviceBatteryMonitor
    var openMusic: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            clock
                .frame(width: 176, alignment: .leading)
                .staggered(0)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)

            HStack(spacing: 10) {
                WeatherCard(service: model.weather).staggered(1)
                BatteryCarousel(mac: batteries.mac, headphones: batteries.headphones).staggered(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: batteries.devices)
        .onAppear { batteries.refresh() }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: ctx.date.timeIntervalSince1970))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ctx.date)
                Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))).capitalizedFirst)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 8)
                nowPlayingChip
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var nowPlayingChip: some View {
        if media.hasTrack {
            Button(action: openMusic) {
                HStack(spacing: 8) {
                    ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 5)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(media.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(media.artist)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    EqualizerView(isPlaying: media.isPlaying, color: media.accent)
                        .frame(width: 13, height: 10)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
            }
            .buttonStyle(PressableStyle())
            .transition(.blurFade)
        }
    }
}

/// Кольцо заряда: при появлении заполняется от нуля.
struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var symbol: String
    var size: CGFloat = 46
    @ViewState private var progress: Double = 0

    private var color: Color {
        if charging { return .green }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: charging ? "bolt.fill" : symbol)
                .font(.system(size: size * 0.33, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, isActive: charging)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.15)) {
                progress = Double(percent) / 100
            }
        }
        .onChange(of: percent) { _, value in
            withAnimation(.spring(response: 0.8)) { progress = Double(value) / 100 }
        }
    }
}

private struct WeatherCard: View {
    @ObservedObject var service: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let w = service.weather {
                HStack(alignment: .top) {
                    Text("\(w.temperature)°")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(w.temperature)))
                    Spacer(minLength: 6)
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 22))
                        .symbolEffect(.pulse, options: .repeating.speed(0.3))
                }
                Text(w.summary)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("↑\(w.high)°  ↓\(w.low)°" + (w.city.map { "  ·  \($0)" } ?? ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                ProgressView().controlSize(.small)
                Text("Погода загружается…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 132, height: 104, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { if let w = service.weather { NSWorkspace.shared.open(w.forecastURL) } }
        .help("Открыть прогноз погоды на несколько дней")
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}


/// Одна карточка заряда, которую можно листать: MacBook ↔ наушники.
private struct BatteryCarousel: View {
    var mac: BatteryInfo?
    var headphones: DeviceBattery?
    @ViewState private var page: Int? = 0

    private var pageCount: Int { headphones == nil ? 1 : 2 }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    macPage
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    if let headphones {
                        headphonesPage(headphones)
                            .containerRelativeFrame(.horizontal)
                            .id(1)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)

            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity((page ?? 0) == i ? 0.9 : 0.25))
                            .frame(width: (page ?? 0) == i ? 14 : 5, height: 5)
                            .onTapGesture { withAnimation(.smooth(duration: 0.35)) { page = i } }
                    }
                }
                .animation(.smooth(duration: 0.25), value: page)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var macPage: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                if mac?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: 60)
            info(title: "MacBook", percent: mac?.percent, note: mac?.charging == true ? "Заряжается" : nil)
        }
        .padding(.horizontal, 14)
    }

    private func headphonesPage(_ device: DeviceBattery) -> some View {
        let level = device.primaryLevel
        let name = device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
        return HStack(spacing: 12) {
            DeviceArt(kind: DeviceArt.Kind(device: device), open: 0, width: 60)
            info(title: name,
                 percent: level?.percent,
                 note: [level?.label == "Кейс" ? "Кейс" : nil, device.isConnected ? nil : "не подключены"]
                    .compactMap { $0 }.joined(separator: " · "))
        }
        .padding(.horizontal, 14)
    }

    private func info(title: String, percent: Int?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            if let percent {
                HStack(spacing: 6) {
                    Text("\(percent)%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    BatteryGlyph(percent: percent)
                }
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
