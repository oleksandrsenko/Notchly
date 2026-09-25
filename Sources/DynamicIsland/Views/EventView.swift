import SwiftUI

/// Всплывающая карточка события, как на iPhone: зарядка MacBook или подключение наушников.
struct EventView: View {
    var event: IslandEvent
    var notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            Group {
                switch event {
                case .charging(let info): ChargingEvent(info: info)
                case .device(let device): DeviceEvent(device: device)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Зарядка

private struct ChargingEvent: View {
    var info: BatteryInfo
    @ViewState private var appeared = false
    @ViewState private var shownPercent = 0

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.green.opacity(0.45), .clear], center: .center,
                                         startRadius: 4, endRadius: 52))
                    .scaleEffect(appeared ? 1.15 : 0.3)
                    .opacity(appeared ? 1 : 0)
                SpinningSymbol(name: "laptopcomputer", size: 50, amplitude: 14)
                    .foregroundStyle(.white)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.green)
                    .shadow(color: .green.opacity(0.8), radius: 8)
                    .symbolEffect(.pulse)
                    .offset(x: 28, y: -24)
                    .scaleEffect(appeared ? 1 : 0.1)
            }
            .frame(width: 92, height: 80)
            .scaleEffect(appeared ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Зарядка")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("MacBook")
                    .font(.system(size: 17, weight: .bold))
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(LinearGradient(colors: [.green.opacity(0.7), .green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 150 * CGFloat(shownPercent) / 100)
                    }
                    .frame(width: 150, height: 8)
                    Text("\(shownPercent)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownPercent)))
                }
            }
            .offset(x: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.08)) { appeared = true }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.25)) { shownPercent = info.percent }
        }
    }
}

// MARK: - Наушники

private struct DeviceEvent: View {
    var device: DeviceBattery
    @ViewState private var appeared = false

    private var isAirPodsWithCase: Bool {
        let n = device.name.lowercased()
        return n.contains("airpods") && !n.contains("max")
    }

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center,
                                         startRadius: 4, endRadius: 52))
                    .scaleEffect(appeared ? 1.1 : 0.3)
                if isAirPodsWithCase {
                    OpenAirPods(pro: device.name.localizedCaseInsensitiveContains("pro"), appeared: appeared)
                } else {
                    SpinningSymbol(name: device.symbol, size: 54, amplitude: 26)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 104, height: 84)
            .scaleEffect(appeared ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Подключено")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(device.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                if device.levels.isEmpty {
                    Text("Заряд появится через пару секунд")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    HStack(spacing: 12) {
                        ForEach(device.levels) { level in
                            HStack(spacing: 5) {
                                BatteryRing(percent: level.percent, charging: level.charging,
                                            symbol: level.symbol.isEmpty ? device.symbol : level.symbol, size: 30)
                                Text("\(level.percent)%")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .offset(x: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.08)) { appeared = true }
        }
    }
}

/// Открытый кейс AirPods: наушники вылетают из кейса и парят по бокам, всё слегка вращается.
private struct OpenAirPods: View {
    var pro: Bool
    var appeared: Bool

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Image(systemName: pro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill")
                    .font(.system(size: 38, weight: .regular))
                    .offset(y: 14)
                Image(systemName: pro ? "airpodpro.left" : "airpod.left")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(-12 + sin(t * 2.1) * 4))
                    .offset(x: appeared ? -30 : 0, y: appeared ? -4 + sin(t * 2.3) * 3 : 10)
                    .scaleEffect(appeared ? 1 : 0.3)
                Image(systemName: pro ? "airpodpro.right" : "airpod.right")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(12 + sin(t * 2.1 + 1) * 4))
                    .offset(x: appeared ? 30 : 0, y: appeared ? -4 + sin(t * 2.3 + 1.4) * 3 : 10)
                    .scaleEffect(appeared ? 1 : 0.3)
            }
            .foregroundStyle(.white)
            .rotation3DEffect(.degrees(sin(t * 1.4) * 18), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
    }
}

/// Символ, который плавно покачивается вокруг вертикальной оси, как 3D-модель на iPhone.
private struct SpinningSymbol: View {
    var name: String
    var size: CGFloat
    var amplitude: Double

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Image(systemName: name)
                .font(.system(size: size, weight: .regular))
                .rotation3DEffect(.degrees(sin(t * 1.5) * amplitude), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .offset(y: sin(t * 2) * 2)
        }
    }
}
