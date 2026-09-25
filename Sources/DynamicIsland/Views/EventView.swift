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
            case .notification(let item):
                NotificationEvent(item: item)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxHeight: .infinity)
            case .reminder(let reminder):
                ReminderEvent(reminder: reminder, onClose: onClose)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Напоминание

private struct ReminderEvent: View {
    var reminder: Reminder
    var onClose: () -> Void
    @ViewState private var appeared = false

    private var isCalendar: Bool { reminder.source == .calendar }

    private var linkTitle: String {
        guard isCalendar else { return "Открыть" }
        let host = reminder.link?.host ?? ""
        return ["zoom", "meet.google", "teams", "facetime", "telemost"].contains { host.contains($0) } ? "Подключиться" : "Открыть"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCalendar ? "calendar" : "checklist")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isCalendar ? Color.red.gradient : Color.orange.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Через \(reminder.minutesBefore) мин · \(reminder.date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            Spacer(minLength: 6)
            if let link = reminder.link {
                Button {
                    NSWorkspace.shared.open(link)
                    onClose()
                } label: {
                    Text(linkTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(isCalendar ? Color.green : Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Уведомление

private struct NotificationEvent: View {
    var item: AppNotification
    @ViewState private var appeared = false

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.bundleID == AppNotification.gmailID {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.red.gradient))
                } else if let url = appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "app.badge.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.subtitle.isEmpty ? item.title : "\(item.title) · \(item.subtitle)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("сейчас")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Зарядка

private struct ChargingEvent: View {
    var info: BatteryInfo
    @ViewState private var appeared = false
    @ViewState private var shownPercent = 0

    var body: some View {
        HStack(spacing: 22) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.green)
                    .offset(x: 10, y: -8)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 92, height: 80)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)

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
                            .fill(Color.green)
                            .frame(width: 150 * CGFloat(shownPercent) / 100)
                    }
                    .frame(width: 150, height: 8)
                    Text("\(shownPercent)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownPercent)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 10)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.45).delay(0.1)) { appeared = true }
            withAnimation(.smooth(duration: 0.9).delay(0.3)) { shownPercent = info.percent }
        }
    }
}

// MARK: - Наушники (карточка как на iPhone)

private struct DeviceSheet: View {
    var device: DeviceBattery
    var onClose: () -> Void
    @ViewState private var appeared = false
    @ViewState private var lidOpen: CGFloat = 0
    @ViewState private var detailsShown = false

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

            DeviceArt(kind: DeviceArt.Kind(device: device), open: lidOpen, width: 150)
                .frame(height: 118)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)

            batteryRow
                .opacity(detailsShown ? 1 : 0)

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
            .opacity(detailsShown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.4).delay(0.12)) { appeared = true }
            // Как на iPhone: сначала кейс, затем плавно открывается крышка.
            withAnimation(.easeInOut(duration: 0.7).delay(0.45)) { lidOpen = 1 }
            withAnimation(.smooth(duration: 0.4).delay(0.75)) { detailsShown = true }
        }
    }

    @ViewBuilder
    private var batteryRow: some View {
        if device.levels.isEmpty {
            Text("Подключено")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        } else {
            HStack(spacing: 18) {
                ForEach(device.levels) { level in
                    HStack(spacing: 6) {
                        Image(systemName: level.symbol.isEmpty ? device.symbol : level.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 18)
                            .help(level.label)
                        BatteryGlyph(percent: level.percent)
                        Text("\(level.percent)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }
}

/// Маленькая батарейка, которая заполняется при появлении.
/// Значок батареи. Во время зарядки заливка плавно дорастает до текущего процента,
/// а по ней мягко пробегает световая волна — как на iPhone.
struct BatteryGlyph: View {
    var percent: Int
    var charging = false
    var width: CGFloat = 24
    @ViewState private var fill: CGFloat = 0

    private var height: CGFloat { width * 0.46 }
    private var color: Color { charging ? .green : percent <= 20 ? .red : .green }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                let inner = width - 4
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, inner * fill))
                    .overlay {
                        if charging {
                            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                                let t = ctx.date.timeIntervalSinceReferenceDate
                                let phase = CGFloat((t / 2.2).truncatingRemainder(dividingBy: 1))
                                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: inner * 0.45)
                                    .offset(x: -inner * 0.45 + phase * inner * 1.45)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: height * 0.16, style: .continuous))
                            .transition(.opacity)
                        }
                    }
                    .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: height * 0.38)
        }
        .onAppear {
            withAnimation(.smooth(duration: 1.2).delay(0.2)) { fill = CGFloat(percent) / 100 }
        }
        .onChange(of: percent) { _, value in
            withAnimation(.smooth(duration: 1.0)) { fill = CGFloat(value) / 100 }
        }
        .animation(.easeInOut(duration: 0.4), value: charging)
    }
}
