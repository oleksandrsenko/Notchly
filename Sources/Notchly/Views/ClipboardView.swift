import SwiftUI

/// История буфера: одна строка на приложение, по клику раскрывается список копирований.
struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ViewState private var expanded: String?
    @ViewState private var copiedID: UUID?

    var body: some View {
        if clipboard.groups.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 22, weight: .medium))
                Text("Скопируйте что-нибудь — оно появится здесь")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(clipboard.groups) { group in
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                GroupRow(group: group, icon: clipboard.icon(for: group.bundleID),
                                         isExpanded: expanded == group.id) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                                        expanded = expanded == group.id ? nil : group.id
                                    }
                                }
                                DismissButton(help: "Удалить всё из \(group.appName)") {
                                    clipboard.remove(group: group)
                                }
                            }
                            if expanded == group.id {
                                VStack(spacing: 2) {
                                    ForEach(group.items) { item in
                                        ClipRow(item: item, copied: copiedID == item.id) {
                                            copy(item)
                                        } onDelete: {
                                            clipboard.remove(item)
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .padding(.leading, 30)
                                .transition(.asymmetric(
                                    insertion: .push(from: .top).combined(with: .opacity),
                                    removal: .opacity))
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private func copy(_ item: ClipItem) {
        clipboard.copy(item)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                if copiedID == item.id { copiedID = nil }
            }
        }
    }
}

private struct GroupRow: View {
    var group: ClipGroup
    var icon: NSImage
    var isExpanded: Bool
    var action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(group.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(group.items.first.map { $0.text.oneLine } ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .opacity(isExpanded ? 0 : 1)
                Spacer(minLength: 6)
                Text("\(group.items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .contentTransition(.numericText())
                Text(shortTimestamp(group.latest))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isExpanded ? 0.1 : (hovering ? 0.07 : 0.03))))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

private struct ClipRow: View {
    var item: ClipItem
    var copied: Bool
    var onCopy: () -> Void
    var onDelete: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.text.oneLine)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            ZStack {
                if copied {
                    Label("Скопировано", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else {
                    Text(shortTimestamp(item.date))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(copied ? Color.green.opacity(0.14) : .white.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help("Нажмите, чтобы скопировать")
    }
}

private extension String {
    var oneLine: String {
        split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
