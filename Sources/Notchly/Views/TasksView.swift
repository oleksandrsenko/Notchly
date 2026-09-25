import SwiftUI

/// Список дел с кружками-чекбоксами и строкой Gemini, который сам раскладывает планы по задачам.
struct TasksView: View {
    @ObservedObject var store: TasksStore
    @ObservedObject var gemini: GeminiAssistant
    var focus: FocusTimer
    @ViewState private var draft = ""
    @FocusState private var draftFocused: Bool
    /// Задача, у которой открыто описание.
    @ViewState private var openedID: UUID? = SnapshotFlags.openedTask

    var body: some View {
        ZStack {
            if let id = openedID, let task = store.items.first(where: { $0.id == id }) {
                TaskDetailView(task: task, store: store, focus: focus) { close() }
                    .transition(.opacity.combined(with: .offset(y: 10)))
            } else {
                list.transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: openedID)
    }

    private func close() { openedID = nil }

    private var list: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                addRow
                // Мини-планер: страница на каждый день недели, листается свайпом или выбором дня в шапке.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<TasksStore.days, id: \.self) { offset in
                            dayPage(offset)
                                .containerRelativeFrame(.horizontal)
                                .id(offset)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(get: { store.selectedDay },
                                            set: { if let day = $0 { store.selectedDay = day } }))
            }
            .frame(maxWidth: .infinity)

            GeminiPanel(gemini: gemini, store: store)
                .frame(width: 236)
        }
    }

    @ViewBuilder
    private func dayPage(_ offset: Int) -> some View {
        let items = store.tasks(forOffset: offset)
        if items.isEmpty {
            Text(offset == 0 ? "Задач на сегодня нет" : "На \(TasksView.dayTitle(offset, lowercased: true)) задач нет")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(items) { task in
                        TaskRow(task: task) { store.toggle(task.id) } onDelete: { store.remove(task.id) }
                            onEdit: { store.update(task.id, text: $0) }
                            onOpen: { openedID = task.id }
                            onFocus: { focus.start(taskID: task.id, title: task.text) }
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
            }
        }
    }

    /// «Сегодня», «Завтра», дальше — день недели и число: «Вс, 27».
    static func dayTitle(_ offset: Int, lowercased: Bool = false) -> String {
        switch offset {
        case 0: return lowercased ? "сегодня" : "Сегодня"
        case 1: return lowercased ? "завтра" : "Завтра"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = lowercased ? "d MMMM" : "EE, d"
            let text = f.string(from: TasksStore.date(forOffset: offset))
            return lowercased ? text : text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(draftFocused ? 0.8 : 0.35))
            TextField(store.selectedDay == 0 ? "Новая задача" : "Задача на \(TasksView.dayTitle(store.selectedDay, lowercased: true))",
                      text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($draftFocused)
                .onSubmit {
                    store.add(draft)
                    draft = ""
                    draftFocused = true
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(draftFocused ? 0.09 : 0.05)))
        .animation(.easeOut(duration: 0.2), value: draftFocused)
    }
}

private struct TaskRow: View {
    var task: TaskItem
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onEdit: (String) -> Void
    var onOpen: () -> Void
    var onFocus: () -> Void
    @ViewState private var hovering = false
    @ViewState private var editing = false
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    private func commit() {
        guard editing else { return }
        editing = false
        if draft != task.text { onEdit(draft) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(task.done ? 0 : 0.45), lineWidth: 1.5)
                    if task.done {
                        Circle().fill(Color.green)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.black)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())

            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else {
                // Нажатие на текст — исправить задачу.
                Text(task.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(task.done ? 0.35 : 0.9))
                    .strikethrough(task.done, color: .white.opacity(0.35))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = task.text + (task.time.map { " \($0)" } ?? "")
                        editing = true
                        DispatchQueue.main.async { focused = true }
                    }
                    .help("Нажмите, чтобы исправить")
            }
            Spacer(minLength: 4)
            // Таймер — начать фокус «Помидор» над этой задачей.
            if !editing && hovering && !task.done {
                Button(action: onFocus) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Фокус 25 минут над этой задачей")
                .transition(.opacity)
            }
            // Стрелочка вниз — описание задачи. Если описание уже есть, она видна всегда.
            if !editing && (hovering || task.notes != nil) {
                Button(action: onOpen) {
                    Image(systemName: task.notes == nil ? "chevron.down" : "text.alignleft")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering ? 0.8 : 0.4))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(task.notes == nil ? "Добавить описание" : "Открыть описание")
                .transition(.opacity)
            }
            ZStack(alignment: .trailing) {
                if let time = task.time {
                    Text(time)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(task.done ? 0.3 : 0.7))
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .opacity(hovering || editing ? 0 : 1)
                }
                if hovering && !editing {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Удалить задачу")
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(editing ? 0.1 : hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

// MARK: - Описание задачи

/// Описание задачи во всю ширину вкладки: сверху название и время, ниже — текст со ссылками.
private struct TaskDetailView: View {
    var task: TaskItem
    @ObservedObject var store: TasksStore
    var focus: FocusTimer
    var onClose: () -> Void
    @ViewState private var notes: String?

    private var text: String { notes ?? task.notes ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help("Свернуть описание")

                Text(task.text)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let time = task.time {
                    Text(time)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                Spacer(minLength: 6)
                Button { focus.start(taskID: task.id, title: task.text) } label: {
                    Label("Фокус", systemImage: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help("Фокус 25 минут над этой задачей")
                // Ссылки из описания — одним нажатием.
                ForEach(Array(TaskItem.links(in: text).prefix(3).enumerated()), id: \.offset) { _, url in
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Ссылка", systemImage: "link")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .frame(maxWidth: 150)
                            .background(Capsule().fill(.white))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .help(url.absoluteString)
                }
            }

            ZStack(alignment: .topLeading) {
                PlainNotesEditor(initial: task.notes ?? "") { value in
                    notes = value
                    store.updateNotes(task.id, value)
                }
                if text.isEmpty {
                    Text("Описание: что сделать, ссылка на урок, заметки…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
        }
        .onExitCommand(perform: onClose)
    }
}

/// Простой текстовый редактор для описания: ссылки подсвечиваются и открываются кликом.
private struct PlainNotesEditor: NSViewRepresentable {
    var initial: String
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12.5)
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 4, height: 7)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.link.rawValue
        tv.linkTextAttributes = [.foregroundColor: NSColor.systemBlue,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        tv.string = initial
        tv.checkTextInDocument(nil)
        tv.delegate = context.coordinator
        // Сразу ставим курсор в конец — можно печатать.
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onChange(tv.string)
        }
    }
}

// MARK: - Gemini

private struct GeminiPanel: View {
    @ObservedObject var gemini: GeminiAssistant
    @ObservedObject var store: TasksStore
    @ViewState private var prompt = ""
    @ViewState private var key = ""
    @ViewState private var added = 0

    private static let gradient = LinearGradient(
        colors: [Color(red: 0.35, green: 0.55, blue: 1), Color(red: 0.72, green: 0.45, blue: 1)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Self.gradient)
                    .symbolEffect(.pulse, isActive: gemini.isThinking)
                Text("Gemini")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if gemini.hasKey {
                    Menu {
                        Button("Удалить ключ API", role: .destructive) { gemini.removeKey() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            if gemini.hasKey { chat } else { keyForm }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let error = gemini.error {
                    Text(error).foregroundStyle(.red.opacity(0.85))
                } else if gemini.isThinking {
                    Text("Думаю…").foregroundStyle(.white.opacity(0.45))
                } else if let reply = gemini.reply {
                    Text(reply).foregroundStyle(.white.opacity(0.85))
                } else if added > 0 {
                    Text("Добавлено задач: \(added)").foregroundStyle(.green.opacity(0.85))
                } else {
                    Text("Расскажите о планах: «сегодня в 5 спортзал, в 10 созвон» — разложу по задачам.")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(.system(size: 11))
            .lineLimit(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeOut(duration: 0.2), value: gemini.isThinking)

            HStack(spacing: 6) {
                TextField("Спросить Gemini", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: gemini.isThinking ? "ellipsis" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(prompt.isEmpty ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(Self.gradient)))
                }
                .buttonStyle(PressableStyle())
                .disabled(prompt.isEmpty || gemini.isThinking)
            }
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }

    private var keyForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Вставьте ключ API из Google AI Studio. Он хранится в Связке ключей.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                SecureField("Ключ API", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit(saveKey)
                Button("Сохранить", action: saveKey)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(key.isEmpty ? .white.opacity(0.3) : .green)
                    .disabled(key.isEmpty)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(0.08)))
            Button("Получить ключ →") {
                NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(.blue)
        }
    }

    private func saveKey() {
        gemini.setKey(key)
        key = ""
    }

    private func send() {
        let text = prompt
        guard !text.isEmpty else { return }
        prompt = ""
        added = 0
        gemini.ask(text, tasks: store.items) { tasks in
            for task in tasks { store.add(task.text, time: task.time) }
            added = tasks.count
        }
    }
}
