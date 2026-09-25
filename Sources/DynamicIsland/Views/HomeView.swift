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
                .frame(width: 200)
                .staggered(0)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)

            HStack(spacing: 10) {
                WeatherCard(service: model.weather).staggered(1)
                BatteryCarousel(mac: batteries.mac, headphones: batteries.headphones,
                                accessories: batteries.accessories, phone: batteries.phone).staggered(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: batteries.devices)
        .onAppear { batteries.refresh() }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .center, spacing: 2) {
                // Без музыки время стоит по центру своей колонки, с музыкой — наверху, над мини-плеером.
                if !media.hasTrack { Spacer(minLength: 0) }
                // Без анимированной смены цифр: так время всегда остаётся идеально чётким.
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))).capitalizedFirst)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: media.hasTrack ? 6 : 0)
                nowPlayingChip
            }
            .padding(.top, 0)
            .padding(.bottom, 2)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: media.hasTrack)
        }
    }

    @ViewBuilder
    private var nowPlayingChip: some View {
        if media.hasTrack {
            Button(action: openMusic) {
                HStack(spacing: 10) {
                    ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 8)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(media.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(media.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    EqualizerView(isPlaying: media.isPlaying, color: .white)
                        .frame(width: 15, height: 12)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.07)))
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


/// Одна карточка заряда, которую можно листать: MacBook ↔ наушники ↔ мышь и другие устройства ↔ iPhone.
private struct BatteryCarousel: View {
    var mac: BatteryInfo?
    var headphones: DeviceBattery?
    var accessories: [DeviceBattery]
    var phone: PhoneBattery?
    @ViewState private var page: Int? = SnapshotFlags.batteryPage

    private enum Page { case mac, headphones(DeviceBattery), accessory(DeviceBattery), phone(PhoneBattery) }

    private var pages: [Page] {
        var result: [Page] = [.mac]
        if let headphones { result.append(.headphones(headphones)) }
        result += accessories.map(Page.accessory)
        if let phone { result.append(.phone(phone)) }
        return result
    }

    var body: some View {
        let pages = pages
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i])
                            .containerRelativeFrame(.horizontal)
                            // Страница при листании мягко гаснет и чуть уменьшается — без рывков.
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(1 - abs(phase.value) * 0.8)
                                    .scaleEffect(1 - abs(phase.value) * 0.06)
                                    .offset(x: phase.value * -18)
                            }
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)

            if pages.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity((page ?? 0) == i ? 0.9 : 0.25))
                            .frame(width: (page ?? 0) == i ? 14 : 5, height: 5)
                            .contentShape(Rectangle().inset(by: -4))
                            .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { page = i } }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .mac: macPage
        case .headphones(let device): headphonesPage(device)
        case .accessory(let device): accessoryPage(device)
        case .phone(let phone): phonePage(phone)
        }
    }

    private var macPage: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                MacBookArt(width: 58)
                if mac?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 5, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 60)
            info(title: "MacBook", percent: mac?.percent, charging: mac?.charging == true,
                 note: mac?.charging == true ? "Заряжается" : nil)
        }
        .padding(.horizontal, 14)
        .animation(.smooth(duration: 0.4), value: mac?.charging)
    }

    private func accessoryPage(_ device: DeviceBattery) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 60)
            info(title: device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression),
                 percent: device.primaryLevel?.percent, note: nil)
        }
        .padding(.horizontal, 14)
    }

    private func phonePage(_ phone: PhoneBattery) -> some View {
        let minutes = Int(Date().timeIntervalSince(phone.updated) / 60)
        let age = minutes < 1 ? "только что" : minutes < 60 ? "\(minutes) мин назад" : "\(minutes / 60) ч назад"
        return HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "iphone")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                if phone.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 8, y: -4)
                }
            }
            .frame(width: 60)
            info(title: "iPhone", percent: phone.percent, charging: phone.charging, note: phone.charging ? "Заряжается · \(age)" : age)
        }
        .padding(.horizontal, 14)
    }

    private func headphonesPage(_ device: DeviceBattery) -> some View {
        let name = device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
        let parts = device.levels.filter { !$0.label.isEmpty }
        return HStack(spacing: 10) {
            DeviceArt(kind: DeviceArt.Kind(device: device), open: 0, width: 50)
            if parts.count > 1 {
                // Наушники с кейсом: левый, правый и кейс — каждый со своим зарядом, в одной карточке.
                VStack(alignment: .leading, spacing: 5) {
                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(alignment: .top, spacing: 9) {
                        ForEach(parts) { level in budLevel(level) }
                    }
                    if !device.isConnected { disconnectedNote }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let level = device.primaryLevel
                VStack(alignment: .leading, spacing: 3) {
                    info(title: name, percent: level?.percent, note: nil,
                         color: level.map { Self.levelColor($0.percent) })
                    if !device.isConnected { disconnectedNote }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var disconnectedNote: some View {
        Text("Не подключены")
            .font(.system(size: 9.5, weight: .light))
            .foregroundStyle(.white.opacity(0.4))
    }

    /// Цвет заряда: 100% — зелёный, к 20% плавно переходит в красный, ниже 20% — красный.
    static func levelColor(_ percent: Int) -> Color {
        let t = min(max(Double(percent - 20) / 80, 0), 1)
        return Color(hue: 0.33 * t, saturation: 0.72, brightness: 0.95)
    }

    /// Один наушник или кейс: подпись и крупный процент, как у MacBook.
    private func budLevel(_ level: DeviceBattery.Level) -> some View {
        let short = ["Левый": "Л", "Правый": "П"][level.label] ?? level.label
        let color = Self.levelColor(level.percent)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(short)
                if level.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.green)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            Text("\(level.percent)%")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(level.percent)))
                .animation(.smooth(duration: 0.6), value: level.percent)
        }
        .fixedSize()
    }

    private func info(title: String, percent: Int?, charging: Bool = false, note: String?, color: Color? = nil) -> some View {
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
                        .foregroundStyle(color ?? .white)
                        .contentTransition(.numericText(value: Double(percent)))
                        .animation(.smooth(duration: 0.6), value: percent)
                    BatteryGlyph(percent: percent, charging: charging, width: 28)
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
