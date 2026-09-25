import SwiftUI

/// Вкладка «Таймер»: фокус «Помидор», обычный таймер и будильник.
struct TimerView: View {
    enum Mode: String, CaseIterable {
        case focus = "Помидор", timer = "Таймер", alarm = "Будильник"
    }

    var model: IslandModel
    @ObservedObject var focus: FocusTimer
    @ObservedObject var countdown: CountdownTimer
    @ObservedObject var alarms: AlarmStore
    @ObservedObject var tasks: TasksStore
    @ViewState private var mode: Mode = SnapshotFlags.timerMode
    @ViewState private var direction: Edge = .trailing
    @Namespace private var segmentNS

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Button { switchTo(item) } label: {
                        Text(item.rawValue)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(mode == item ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 11)
                            .frame(height: 24)
                            .background(Capsule().fill(.white.opacity(0.08)))
                            .background {
                                if mode == item {
                                    Capsule().fill(.white).matchedGeometryEffect(id: "timer-segment", in: segmentNS)
                                }
                            }
                            .overlay(alignment: .topTrailing) { runningDot(for: item) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
                Text(headerNote)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ZStack {
                switch mode {
                case .focus: focusPage.transition(.pageSlide(direction))
                case .timer: timerPage.transition(.pageSlide(direction))
                case .alarm: alarmPage.transition(.pageSlide(direction))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerNote: String {
        switch mode {
        case .focus: return "Подходов сегодня: \(focus.completedToday)"
        case .timer: return countdown.isActive ? "Идёт отсчёт" : ""
        case .alarm: return alarms.next.map { "Ближайший: \($0.time)" } ?? ""
        }
    }

    /// Точка на разделе, где что-то уже идёт.
    @ViewBuilder
    private func runningDot(for item: Mode) -> some View {
        let running = (item == .focus && focus.isActive) || (item == .timer && countdown.isActive)
            || (item == .alarm && alarms.next != nil)
        if running && mode != item {
            Circle().fill(item == .focus ? FocusCompactView.tint(for: focus.phase)
                          : item == .timer ? CountdownCompactView.tint : .yellow)
                .frame(width: 6, height: 6)
                .offset(x: 1, y: -1)
        }
    }

    private func switchTo(_ item: Mode) {
        guard item != mode else { return }
        let order = Mode.allCases
        direction = (order.firstIndex(of: item) ?? 0) > (order.firstIndex(of: mode) ?? 0) ? .trailing : .leading
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { mode = item }
    }

    // MARK: - Помидор

    private var focusPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 22) {
                BigRing(progress: focus.progress(at: ctx.date), tint: FocusCompactView.tint(for: focus.phase),
                        time: focus.remaining(at: ctx.date).clock, caption: focus.isActive ? focus.phase.title : "25 мин",
                        dimmed: focus.isPaused)
                VStack(alignment: .leading, spacing: 9) {
                    Text(focus.isActive ? (focus.taskTitle ?? "Без задачи") : "Фокус по технике «Помидор»")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("25 мин работы · 5 мин перерыв · 15 мин после каждого 4-го")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    if focus.isActive {
                        HStack(spacing: 8) {
                            RoundButton(symbol: focus.isPaused ? "play.fill" : "pause.fill",
                                        help: focus.isPaused ? "Продолжить" : "Пауза") { focus.togglePause() }
                            RoundButton(symbol: "forward.end.fill",
                                        help: focus.phase.isBreak ? "Закончить перерыв" : "К перерыву") { focus.skip() }
                            RoundButton(symbol: "stop.fill", help: "Остановить") { focus.stop() }
                        }
                    } else {
                        HStack(spacing: 8) {
                            taskMenu
                            PrimaryButton(title: "Начать фокус", symbol: "play.fill") {
                                let task = tasks.items.first { $0.id == selectedTask }
                                model.startFocus(taskID: task?.id, title: task?.text)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                roundDots
            }
        }
    }

    @ViewState private var selectedTask: UUID?

    private var taskMenu: some View {
        let open = tasks.tasks(forOffset: 0).filter { !$0.done }
        let title = open.first { $0.id == selectedTask }?.text ?? "Без задачи"
        return Menu {
            Button("Без задачи") { selectedTask = nil }
            if !open.isEmpty { Divider() }
            ForEach(open) { task in
                Button(task.time.map { "\($0)  \(task.text)" } ?? task.text) { selectedTask = task.id }
            }
        } label: {
            Label(title, systemImage: "checklist")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 11)
        .frame(height: 28)
        .frame(maxWidth: 170)
        .background(Capsule().fill(.white.opacity(0.1)))
        .help("К какой задаче привязать фокус")
    }

    /// Четыре точки — подходы до длинного перерыва.
    private var roundDots: some View {
        let done = focus.completedToday % FocusTimer.roundsBeforeLongBreak
        return VStack(spacing: 6) {
            ForEach(0..<FocusTimer.roundsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < done ? FocusCompactView.tint(for: .work) : .white.opacity(0.14))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.trailing, 6)
        .help("Подходы до длинного перерыва")
    }

    // MARK: - Таймер

    private var timerPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 22) {
                BigRing(progress: countdown.progress(at: ctx.date), tint: CountdownCompactView.tint,
                        time: countdown.remaining(at: ctx.date).clock,
                        caption: countdown.isActive ? (countdown.isPaused ? "Пауза" : "Осталось") : "Таймер",
                        dimmed: countdown.isPaused)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(CountdownTimer.presets, id: \.self) { value in
                            let selected = countdown.minutes == value
                            Button { countdown.setMinutes(value) } label: {
                                Text("\(value)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selected ? .black : .white.opacity(0.75))
                                    .frame(width: 34, height: 26)
                                    .background(Capsule().fill(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1))))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(countdown.isActive)
                        }
                        Text("мин").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                    }
                    .opacity(countdown.isActive ? 0.4 : 1)
                    HStack(spacing: 8) {
                        if countdown.isActive {
                            RoundButton(symbol: countdown.isPaused ? "play.fill" : "pause.fill",
                                        help: countdown.isPaused ? "Продолжить" : "Пауза") { countdown.togglePause() }
                            RoundButton(symbol: "arrow.counterclockwise", help: "Сбросить") { countdown.reset() }
                        } else {
                            RoundButton(symbol: "minus", help: "Минус минута") { countdown.step(-1) }
                            Text("\(countdown.minutes) мин")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(minWidth: 56)
                            RoundButton(symbol: "plus", help: "Плюс минута") { countdown.step(1) }
                            PrimaryButton(title: "Старт", symbol: "play.fill") { countdown.start() }
                                .padding(.leading, 4)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Будильник

    @ViewState private var alarmHour = 7
    @ViewState private var alarmMinute = 30

    private var alarmPage: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    wheel(value: alarmHour, range: 24) { alarmHour = $0 }
                    Text(":").font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    wheel(value: alarmMinute, range: 60, step: 5) { alarmMinute = $0 }
                }
                PrimaryButton(title: "Добавить", symbol: "alarm.fill") {
                    alarms.add(String(format: "%02d:%02d", alarmHour, alarmMinute))
                }
            }
            .frame(width: 150)

            Group {
                if alarms.alarms.isEmpty {
                    Text("Будильников нет. Выберите время слева и нажмите «Добавить».")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(alarms.alarms) { alarm in AlarmRow(alarm: alarm, store: alarms) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Число со стрелками вверх/вниз (часы или минуты).
    private func wheel(value: Int, range: Int, step: Int = 1, set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            Button { set((value + step) % range) } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                    .frame(width: 44, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Text(String(format: "%02d", value))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button { set((value - step + range) % range) } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    .frame(width: 44, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

// MARK: - Детали

/// Большое кольцо с отсчётом в центре.
private struct BigRing: View {
    var progress: Double
    var tint: Color
    var time: String
    var caption: String
    var dimmed = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 0) {
                Text(time)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? .white.opacity(0.5) : .white)
                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(width: 104, height: 104)
    }
}

private struct RoundButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
                .background(Capsule().fill(.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

private struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(.white))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(PressableStyle())
    }
}

private struct AlarmRow: View {
    var alarm: Alarm
    @ObservedObject var store: AlarmStore
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(alarm.enabled ? .yellow : .white.opacity(0.3))
            Text(alarm.time)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(alarm.enabled ? .white : .white.opacity(0.35))
            Spacer()
            if hovering {
                Button { store.remove(alarm.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Удалить будильник")
            }
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { _ in store.toggle(alarm.id) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.yellow)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0.05)))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}
