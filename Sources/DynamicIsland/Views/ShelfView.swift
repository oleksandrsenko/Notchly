import SwiftUI
import QuickLookThumbnailing

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    var isTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.items.isEmpty ? "Файлы" : "Файлы · \(store.items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
                Spacer()
                if !store.items.isEmpty {
                    Button("Очистить") { store.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .transition(.opacity)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.white.opacity(isTargeted ? 0.6 : 0.16))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(isTargeted ? 0.08 : 0.03)))
                    .animation(.easeOut(duration: 0.2), value: isTargeted)

                if store.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 24, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: isTargeted)
                        Text("Перетащите файлы сюда, чтобы подержать их под рукой")
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.items) { item in
                                ShelfTile(item: item) { store.remove(item) }
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
        }
    }
}

private struct ShelfTile: View {
    var item: ShelfItem
    var onRemove: () -> Void

    @ViewState private var thumbnail: NSImage?
    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable()
                }
            }
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = h } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Открыть") { NSWorkspace.shared.open(item.url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Отправить по AirDrop") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.url]) }
            Button("Скопировать путь") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Убрать из файлов", role: .destructive, action: onRemove)
        }
        .help(item.url.path)
        .task(id: item.url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            withAnimation(.easeOut(duration: 0.25)) { thumbnail = rep.nsImage }
        }
    }
}
