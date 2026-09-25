import SwiftUI

struct NotesView: View {
    @ObservedObject var store: NotesStore
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack {
                    Text("Заметки")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    IconButton(systemName: "square.and.pencil", size: 12, padding: 5) {
                        store.create()
                        editorFocused = true
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
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
                        .id(id)
                        .transition(.opacity)
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
        .onDisappear { store.persist() }
    }
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
                Text(note.updatedAt, format: .relative(presentation: .named))
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
