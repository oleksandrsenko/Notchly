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
    @ViewState private var direction: Edge = .trailing
    @FocusState private var editorFocused: Bool
    @ViewState private var mode: Mode = .notes
    @Namespace private var segmentNS

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(Mode.segments, id: \.self) { item in
                        Button { switchTo(item) } label: {
                            Text(item.rawValue)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(mode == item ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .frame(height: 22)
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
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.08)))

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
                    IconButton(systemName: "square.and.pencil", size: 12, padding: 5) {
                        store.create()
                        editorFocused = true
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .transition(.blurFade)
                } else if mode == .tasks && tasks.items.contains(where: \.done) {
                    Button("Убрать выполненные") { tasks.clearDone() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
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
                case .tasks: TasksView(store: tasks, gemini: gemini).transition(.pageSlide(direction))
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
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 160)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(editorFocused ? 0.09 : 0.06))
                if let id = store.selectedID {
                    TextEditor(text: store.binding(for: id))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($editorFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(id)
                    if store.selected?.text.isEmpty ?? true {
                        Text("Начните печатать…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .fixedSize()
                            .allowsHitTesting(false)
                            .transaction { $0.animation = nil }
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
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                    .lineLimit(1)
                Text(shortTimestamp(note.updatedAt))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            if hovering {
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
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}
