import SwiftUI

/// Главная: часы, дата, мини-плеер и заряд Mac и подключённых устройств.
struct HomeView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @ObservedObject var batteries: DeviceBatteryMonitor
    var openMusic: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            clock
                .frame(width: 200, alignment: .leading)
                .staggered(0)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let mac = batteries.mac {
                        BatteryCard(name: "MacBook", levels: [
                            .init(label: mac.charging ? "Заряжается" : "", symbol: "laptopcomputer",
                                  percent: mac.percent, charging: mac.charging),
                        ], fallbackSymbol: "laptopcomputer")
                        .staggered(1)
                    }
                    ForEach(Array(batteries.devices.enumerated()), id: \.element.id) { i, device in
                        BatteryCard(name: device.name, levels: device.levels, fallbackSymbol: device.symbol)
                            .staggered(2 + i)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if batteries.devices.isEmpty {
                        NoDevicesCard().staggered(2)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: batteries.devices)
        .onAppear { batteries.refresh() }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
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

private struct BatteryCard: View {
    var name: String
    var levels: [DeviceBattery.Level]
    var fallbackSymbol: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(levels) { level in
                    VStack(spacing: 5) {
                        BatteryRing(percent: level.percent, charging: level.charging,
                                    symbol: level.symbol.isEmpty ? fallbackSymbol : level.symbol)
                        Text(level.label.isEmpty ? "\(level.percent)%" : "\(level.label) · \(level.percent)%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 96)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
    }
}

/// Кольцо заряда: при появлении заполняется от нуля.
private struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var symbol: String
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, isActive: charging)
        }
        .frame(width: 46, height: 46)
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

private struct NoDevicesCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 46, height: 46)
            Text("Наушники\nне подключены")
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.04)))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
