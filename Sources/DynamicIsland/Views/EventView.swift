import SwiftUI

/// Всплывающая карточка события, как на iPhone: зарядка MacBook или подключение наушников.
struct EventView: View {
    var event: IslandEvent
    var notchHeight: CGFloat
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            switch event {
            case .charging(let info):
                ChargingEvent(info: info)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 16)
                    .frame(maxHeight: .infinity)
            case .device(let device):
                DeviceSheet(device: device, onClose: onClose)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                    .frame(maxHeight: .infinity)
            }
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

// MARK: - Наушники (карточка как на iPhone)

private struct DeviceSheet: View {
    var device: DeviceBattery
    var onClose: () -> Void
    @ViewState private var appeared = false

    /// «AirPods Max (Alexander)» → «AirPods Max», как на iPhone.
    private var title: String {
        device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 36)
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -6)

            DeviceIllustration(device: device, appeared: appeared)
                .frame(height: 112)
                .padding(.top, 2)

            batteryRow
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer(minLength: 10)

            Button(action: onClose) {
                Text("Готово")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260)
                    .frame(height: 36)
                    .background(Capsule().fill(Color(red: 0.2, green: 0.47, blue: 1)))
            }
            .buttonStyle(PressableStyle())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.1)) { appeared = true }
        }
    }

    @ViewBuilder
    private var batteryRow: some View {
        if device.levels.isEmpty {
            Text("Подключено")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        } else {
            HStack(spacing: 18) {
                ForEach(device.levels) { level in
                    HStack(spacing: 6) {
                        Image(systemName: level.symbol.isEmpty ? device.symbol : level.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                        BatteryGlyph(percent: level.percent)
                        Text("\(level.percent)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

/// Маленькая батарейка, которая заполняется при появлении.
private struct BatteryGlyph: View {
    var percent: Int
    @ViewState private var fill: CGFloat = 0

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(percent <= 20 ? Color.red : Color.green)
                    .frame(width: max(2, 18 * fill))
                    .padding(2)
            }
            .frame(width: 24, height: 11)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.35)) {
                fill = CGFloat(percent) / 100
            }
        }
    }
}

/// «Модель» устройства: металлический градиент, мягкая тень снизу и медленное вращение.
private struct DeviceIllustration: View {
    var device: DeviceBattery
    var appeared: Bool

    private var isAirPodsWithCase: Bool {
        let n = device.name.lowercased()
        return n.contains("airpods") && !n.contains("max")
    }

    private var metal: LinearGradient {
        LinearGradient(colors: [Color(white: 1), Color(white: 0.78), Color(white: 0.93), Color(white: 0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                RadialGradient(colors: [.white.opacity(0.14), .clear], center: .center, startRadius: 2, endRadius: 90)
                Ellipse()
                    .fill(.black.opacity(0.9))
                    .frame(width: 110 - sin(t * 1.8) * 6, height: 10)
                    .blur(radius: 6)
                    .overlay(Ellipse().fill(.white.opacity(0.06)).frame(width: 90, height: 6).blur(radius: 4))
                    .offset(y: 50)
                Group {
                    if isAirPodsWithCase {
                        let pro = device.name.localizedCaseInsensitiveContains("pro")
                        ZStack {
                            Image(systemName: pro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill")
                                .font(.system(size: 62))
                                .offset(y: 16)
                            Image(systemName: pro ? "airpodpro.left" : "airpod.left")
                                .font(.system(size: 36))
                                .rotationEffect(.degrees(-14 + sin(t * 2) * 4))
                                .offset(x: appeared ? -50 : 0, y: appeared ? -14 + sin(t * 2.2) * 3 : 14)
                            Image(systemName: pro ? "airpodpro.right" : "airpod.right")
                                .font(.system(size: 36))
                                .rotationEffect(.degrees(14 + sin(t * 2 + 1) * 4))
                                .offset(x: appeared ? 50 : 0, y: appeared ? -14 + sin(t * 2.2 + 1.3) * 3 : 14)
                        }
                    } else {
                        Image(systemName: device.symbol)
                            .font(.system(size: 88, weight: .light))
                    }
                }
                .foregroundStyle(metal)
                .shadow(color: .white.opacity(0.12), radius: 12)
                .rotation3DEffect(.degrees(sin(t * 0.9) * 24), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .offset(y: sin(t * 1.8) * 3)
            }
            .scaleEffect(appeared ? 1 : 0.55)
            .opacity(appeared ? 1 : 0)
            .blur(radius: appeared ? 0 : 8)
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
