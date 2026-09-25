import SwiftUI

/// Список дел с кружками-чекбоксами и строкой Gemini, который сам раскладывает планы по задачам.
struct TasksView: View {
    @ObservedObject var store: TasksStore
    @ObservedObject var gemini: GeminiAssistant
    @ViewState private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                addRow
                if store.items.isEmpty {
                    Text("Задач пока нет")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 1) {
                            ForEach(store.sorted) { task in
                                TaskRow(task: task) { store.toggle(task.id) } onDelete: { store.remove(task.id) }
                                    onEdit: { store.update(task.id, text: $0) }
                                    .transition(.opacity.combined(with: .offset(y: -4)))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            GeminiPanel(gemini: gemini, store: store)
                .frame(width: 236)
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(draftFocused ? 0.8 : 0.35))
            TextField("Новая задача", text: $draft)
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
