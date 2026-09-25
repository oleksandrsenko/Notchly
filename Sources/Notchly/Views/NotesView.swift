import SwiftUI

struct NotesView: View {
    enum Mode: String, CaseIterable {
        case notes = "Заметки", tasks = "Задачи", clipboard = "Буфер обмена", vault = "API-ключи"
        static let segments: [Mode] = [.notes, .tasks, .clipboard]
        var order: Int { Mode.allCases.firstIndex(of: self) ?? 0 }
    }

    @ObservedObject var store: NotesStore
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var vault: KeyVault
    @ObservedObject var tasks: TasksStore
    var gemini: GeminiAssistant
    var focus: FocusTimer
    var calendar: CalendarService? = nil
    @ViewState private var direction: Edge = .trailing
    @ViewState private var richController = RichTextController()
    @FocusState private var editorFocused: Bool
    @ViewState private var mode: Mode = SnapshotFlags.notesMode
    @Namespace private var segmentNS

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Каждый раздел — отдельная капсула с промежутком: «Задачи» стоят отдельно, посередине.
                HStack(spacing: 8) {
                    ForEach(Mode.segments, id: \.self) { item in
                        Button { switchTo(item) } label: {
                            Text(item.rawValue)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(mode == item ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 11)
                                .frame(height: 24)
                                .background(Capsule().fill(.white.opacity(0.08)))
                                .background {
                                    if mode == item {
                                        Capsule().fill(.white).matchedGeometryEffect(id: "segment", in: segmentNS)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                // Кнопка ключей «выезжает» рядом, когда открыт буфер обмена.
                if mode == .clipboard || mode == .vault {
                    Button { switchTo(mode == .vault ? .clipboard : .vault) } label: {
                        Label("API-ключи", systemImage: vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(mode == .vault ? .black : .yellow.opacity(0.9))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(mode == .vault ? Color.yellow : Color.yellow.opacity(0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.6, anchor: .leading)),
                        removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading))))
                }

                Spacer()

                if mode == .notes {
                    FormatBar(controller: richController)
                        .transition(.opacity)
                    IconButton(systemName: "square.and.pencil", size: 12, padding: 5) {
                        store.create()
                        editorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let tv = richController.textView { tv.window?.makeFirstResponder(tv) }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .transition(.blurFade)
                } else if mode == .tasks {
                    DayStrip(store: tasks)
                        .transition(.opacity)
                } else if mode == .clipboard && !clipboard.groups.isEmpty {
                    Button("Очистить") { clipboard.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .transition(.blurFade)
                }
            }

            ZStack {
                switch mode {
                case .notes: notes.transition(.pageSlide(direction))
                case .tasks: TasksView(store: tasks, gemini: gemini, focus: focus, onAppear: { calendar?.requestIfNeeded() })
                    .transition(.pageSlide(direction))
                case .clipboard: ClipboardView(clipboard: clipboard).transition(.pageSlide(direction))
                case .vault: KeyVaultView(vault: vault).transition(.pageSlide(direction))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            store.persist()
            vault.lock()
        }
    }

    private func switchTo(_ item: Mode) {
        guard item != mode else { return }
        direction = item.order > mode.order ? .trailing : .leading
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { mode = item }
    }

    private var notes: some View {
        HStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(store.notes) { note in
                        NoteRow(note: note, selected: note.id == store.selectedID) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.selectedID = note.id
                            }
                        } onDelete: {
                            store.delete(note.id)
                        } onRename: { store.rename(note.id, to: $0) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 160)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(editorFocused ? 0.09 : 0.06))
                if let id = store.selectedID {
                    RichTextEditor(initial: store.attributed(for: id), controller: richController) { value in
                        store.updateRich(id, value)
                    }
                    .focused($editorFocused)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(id)
                    if store.selected?.text.isEmpty ?? true {
                        Text("Начните печатать…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: editorFocused)
            .onTapGesture { editorFocused = true }
        }
    }
}

/// Короткое время: сегодня — «15:42», раньше — «24 сент., 15:42».
func shortTimestamp(_ date: Date) -> String {
    let ru = Locale(identifier: "ru_RU")
    if Calendar.current.isDateInToday(date) {
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ru))
    }
    return date.formatted(.dateTime.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ru))
}

private struct NoteRow: View {
    var note: Note
    var selected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onRename: (String) -> Void
    @ViewState private var hovering = false
    @ViewState private var renaming = false
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    private func startRename() {
        draft = note.title
        renaming = true
        DispatchQueue.main.async { focused = true }
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        onRename(draft)
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField("Название", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .focused($focused)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = false }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commitRename() } }
                } else {
                    Text(note.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                        .lineLimit(1)
                }
                Text(shortTimestamp(note.updatedAt))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            if hovering && !renaming {
                Button(action: startRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Переименовать")
                .transition(.opacity)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(selected ? 0.14 : (hovering ? 0.07 : 0))))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: startRename)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Переименовать", action: startRename)
            Button("Удалить", role: .destructive, action: onDelete)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Дни мини-планера в шапке задач: «Сегодня», «Завтра» и дальше дни недели — максимум неделя вперёд.
private struct DayStrip: View {
    @ObservedObject var store: TasksStore
    @Namespace private var ns

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EE"
        return f
    }()

    private func title(_ offset: Int) -> String {
        switch offset {
        case 0: return "Сегодня"
        case 1: return "Завтра"
        default:
            let text = Self.weekday.string(from: TasksStore.date(forOffset: offset))
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<TasksStore.days, id: \.self) { offset in
                let selected = store.selectedDay == offset
                let open = store.openCount(forOffset: offset)
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { store.selectedDay = offset }
                } label: {
                    Text(title(offset))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .black : .white.opacity(0.6))
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background {
                            if selected {
                                Capsule().fill(.white).matchedGeometryEffect(id: "day", in: ns)
                            }
                        }
                        // Точка — в этот день есть невыполненные задачи.
                        .overlay(alignment: .bottom) {
                            if open > 0 && !selected {
                                Circle().fill(.white.opacity(0.55)).frame(width: 3, height: 3).offset(y: -1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help(TasksView.dayTitle(offset, lowercased: offset > 1) + (open > 0 ? " · задач: \(open)" : ""))
            }
            if store.tasks(forOffset: store.selectedDay).contains(where: \.done) {
                Button { store.clearDone() } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Убрать выполненные")
                .transition(.opacity)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.06)))
        .fixedSize()
    }
}
