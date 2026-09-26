import SwiftUI

/// Всплывающая карточка события, как на iPhone: зарядка MacBook или подключение наушников.
struct EventView: View {
    var event: IslandEvent
    var model: IslandModel
    var onClose: () -> Void

    private var notchHeight: CGFloat { model.notchSize.height }

    var body: some View {
        if case .device(let device) = event {
            CompactDeviceEvent(device: device, notchWidth: model.notchSize.width)
        } else {
            VStack(spacing: 0) {
                Color.clear.frame(height: notchHeight)
                card
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch event {
        case .charging(let info):
            ChargingEvent(info: info)
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
        case .device, .deviceSheet:
            if case .deviceSheet(let device) = event {
                DeviceSheet(device: device, onClose: onClose)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                    .frame(maxHeight: .infinity)
            }
        case .notification(let item):
            NotificationEvent(item: item)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .reminder(let reminder):
            ReminderEvent(reminder: reminder, model: model, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .focus(let transition):
            FocusEvent(transition: transition, model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .timerDone(let duration):
            ActionCard(symbol: "hourglass.bottomhalf.filled", tint: .orange,
                       title: L("Таймер завершён"),
                       subtitle: duration.durationText) {
                CardButton(title: L("Ещё раз"), systemImage: "arrow.clockwise") {
                    model.countdown.start(seconds: Int(duration.rounded()))
                    model.dismissEvent()
                }
                CardButton(title: L("Готово"), prominent: true) { model.dismissEvent() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        case .alarm(let alarm):
            ActionCard(symbol: "alarm.fill", tint: .yellow, title: L("Будильник · %@", "\(alarm.time)"),
                       subtitle: L("Пора!")) {
                CardButton(title: L("+5 мин")) {
                    model.alarms.snooze()
                    model.dismissEvent()
                }
                CardButton(title: L("Стоп"), systemImage: "stop.fill", prominent: true) { model.dismissEvent() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Небольшая кнопка-капсула для карточек.
private struct CardButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent = false
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10.5, weight: .bold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(prominent ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.14))))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PressableStyle())
    }
}

/// Карточка с иконкой, заголовком, подписью и кнопками справа.
private struct ActionCard<Buttons: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    @ViewBuilder var buttons: () -> Buttons
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) { buttons() }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Наушники подключились (компактно)

/// Как на iPhone: слева наушники в кольце заряда, справа кейс с дугой заряда.
private struct CompactDeviceEvent: View {
    var device: DeviceBattery
    var notchWidth: CGFloat
    @ViewState private var appeared = false

    private var buds: DeviceBattery.Level? {
        let pair = device.levels.filter { $0.label == "Левый" || $0.label == "Правый" }
        return pair.min { $0.percent < $1.percent } ?? (device.levels.count == 1 ? device.levels.first : nil)
    }
    private var casing: DeviceBattery.Level? { device.levels.first { $0.label == "Кейс" } }
    private var caseSymbol: String {
        casing?.symbol.isEmpty == false ? casing!.symbol : "airpodspro.chargingcase.wireless.fill"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Слева наушники: кольцо и процент; справа кейс: процент и кольцо.
            HStack(spacing: 5) {
                ring(level: buds, symbol: device.symbol)
                if let buds { percent(buds.percent) }
            }
            .padding(.leading, 12)
            Spacer(minLength: notchWidth)
            if let casing {
                HStack(spacing: 5) {
                    percent(casing.percent)
                    ring(level: casing, symbol: caseSymbol)
                }
                .padding(.trailing, 12)
            } else if buds == nil {
                Text(L("Подключено"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.trailing, 14)
            }
        }
        .frame(maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.08)) { appeared = true } }
        .help(L("Нажмите, чтобы увидеть заряд подробнее"))
    }

    private func percent(_ value: Int) -> some View {
        Text("\(value)%")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(BatteryTint.color(value))
            .contentTransition(.numericText(value: Double(value)))
            .fixedSize()
    }

    private func ring(level: DeviceBattery.Level?, symbol: String) -> some View {
        ZStack {
            if let level {
                ChargeRing(percent: level.percent, charging: false, size: 24)
            }
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Фокус

private struct FocusEvent: View {
    var transition: FocusTimer.Transition
    var model: IslandModel
    @ViewState private var appeared = false

    private var title: String {
        switch transition {
        case .workFinished(let next, _): return next == .longBreak ? L("Длинный перерыв · 15 мин") : L("Перерыв · 5 мин")
        case .breakFinished: return L("Перерыв окончен")
        }
    }

    private var subtitle: String {
        switch transition {
        case .workFinished(_, let held):
            let done = L("Подходов сегодня: %@", "\(model.focus.completedToday)")
            return held > 0 ? L("%@ · ждут уведомления: %@", "\(done)", "\(held)") : done
        case .breakFinished: return L("Готовы к следующему подходу?")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transition == .breakFinished ? "timer" : "cup.and.saucer.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(transition == .breakFinished ? Color.red.gradient : Color.green.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            switch transition {
            case .workFinished:
                CardButton(title: L("Пропустить")) {
                    model.focus.skip()
                    model.dismissEvent()
                }
            case .breakFinished:
                CardButton(title: L("Начать фокус"), systemImage: "play.fill", prominent: true) {
                    model.startFocus(taskID: model.focus.taskID, title: model.focus.taskTitle)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Напоминание

private struct ReminderEvent: View {
    var reminder: Reminder
    var model: IslandModel
    var onClose: () -> Void
    @ViewState private var appeared = false

    private var isCalendar: Bool { reminder.source == .calendar }

    private var isMeeting: Bool {
        let host = reminder.link?.host ?? ""
        return ["zoom", "meet.google", "teams", "facetime", "telemost"].contains { host.contains($0) }
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
                Text(reminder.subtitle())
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if let link = reminder.link {
                    CardButton(title: isMeeting ? L("Войти") : L("Открыть"),
                               systemImage: isMeeting ? "video.fill" : "link",
                               prominent: true, tint: isMeeting ? .green : .white) {
                        NSWorkspace.shared.open(link)
                        onClose()
                    }
                }
                CardButton(title: L("+5 мин")) { model.snoozeReminder(reminder) }
                    .help(L("Напомнить через 5 минут"))
                if reminder.taskID != nil {
                    CardButton(title: L("Готово"), systemImage: "checkmark",
                               prominent: reminder.link == nil) { model.completeReminder(reminder) }
                }
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
                    Text(L("сейчас"))
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
                Text(L("Зарядка"))
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

    /// «AirPods Max (Имя)» → «AirPods Max», как на iPhone.
    private var title: String {
        device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
    }

    private struct Column: Identifiable {
        enum Art { case pair(pro: Bool), bud(pro: Bool, mirrored: Bool), chargingCase(DeviceArt.Kind), headphones }
        var id: String
        var art: Art
        var level: DeviceBattery.Level?
    }

    /// Как на iPhone: наушники вместе (если заряд одинаковый) или по отдельности, и кейс.
    private var columns: [Column] {
        let kind = DeviceArt.Kind(device: device)
        let pro: Bool
        switch kind {
        case .airPodsPro: pro = true
        case .airPods: pro = false
        case .symbol: return [Column(id: "main", art: .headphones, level: device.primaryLevel)]
        }
        let left = device.levels.first { $0.label == "Левый" }
        let right = device.levels.first { $0.label == "Правый" }
        let casing = device.levels.first { $0.label == "Кейс" }
        var result: [Column] = []
        if let left, let right, left.percent != right.percent {
            result.append(Column(id: "L", art: .bud(pro: pro, mirrored: false), level: left))
            result.append(Column(id: "R", art: .bud(pro: pro, mirrored: true), level: right))
        } else if let bud = [left, right].compactMap({ $0 }).min(by: { $0.percent < $1.percent }) {
            var level = bud
            level.charging = (left?.charging ?? false) || (right?.charging ?? false)
            result.append(Column(id: "buds", art: .pair(pro: pro), level: level))
        } else {
            result.append(Column(id: "buds", art: .pair(pro: pro), level: nil))
        }
        result.append(Column(id: "case", art: .chargingCase(kind), level: casing))
        return result
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

            Spacer(minLength: 6)

            let columns = columns
            HStack(alignment: .bottom, spacing: columns.count > 2 ? 26 : 44) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    VStack(spacing: 8) {
                        art(column.art)
                            .frame(height: 86)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.smooth(duration: 0.5).delay(0.15 + Double(index) * 0.08), value: appeared)
                        if let level = column.level {
                            ChargeRing(percent: level.percent, charging: level.charging, size: 28)
                            Text("\(level.percent) %")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.9))
                        } else {
                            Text(L("Подключено"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.4).delay(0.12)) { appeared = true } }
    }

    @ViewBuilder
    private func art(_ art: Column.Art) -> some View {
        switch art {
        case .pair(let pro):
            EarbudPair(pro: pro, height: 86)
        case .bud(let pro, let mirrored):
            EarbudArt(pro: pro)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .scaleEffect(86 / 92)
                .frame(width: 56, height: 86)
        case .chargingCase(let kind):
            DeviceArt(kind: kind, open: 0, width: 98)
        case .headphones:
            DeviceArt(kind: DeviceArt.Kind(device: device), open: 0, width: 98)
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
    /// Белая заливка без зелёного и красного — для карточки наушников.
    var monochrome = false

    private var height: CGFloat { width * 0.46 }
    private var color: Color {
        if monochrome { return .white.opacity(0.9) }
        return charging ? .green : percent <= 20 ? .red : .green
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                // Статичная заливка без анимаций: так батарейка ничего не стоит процессору.
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, (width - 4) * CGFloat(percent) / 100))
                    .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: height * 0.38)
        }
    }
}
