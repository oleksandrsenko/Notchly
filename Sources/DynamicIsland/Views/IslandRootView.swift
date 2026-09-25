import SwiftUI
import UniformTypeIdentifiers

/// Форма выреза: плавные «уши» у верхней кромки и скруглённый низ.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, (rect.height - t) , (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        VStack(spacing: 0) {
            content
                // Ширина и высота анимируются раздельно: при раскрытии остров сначала расширяется вдоль кромки,
                // затем опускается — движение идёт сверху вниз, а не из стороны в сторону.
                .animation(model.widthAnimation) { $0.frame(width: model.bodySize.width) }
                .animation(model.heightAnimation) { $0.frame(height: model.bodySize.height, alignment: .top) }
                .padding(.horizontal, model.topRadius)
                .clipShape(shape)
                // Тень рисуем только у фона. Если повесить её на весь остров,
                // SwiftUI отбрасывает тень от каждой надписи, и текст выглядит размытым.
                .background {
                    shape
                        .fill(Color.black)
                        .shadow(color: .black.opacity(model.isExpanded || model.event != nil ? 0.5 : 0), radius: 16, y: 6)
                }
                .overlay {
                    // Подсветка краёв при перетаскивании файла.
                    shape.stroke(Color.white.opacity(model.isDropTargeted ? 0.35 : 0), lineWidth: 1.5)
                }
                .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted, perform: handleDrop)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.isExpanded ? IslandMetrics.expandHeight : IslandMetrics.collapseHeight, value: model.isExpanded)
        .animation(IslandMetrics.softSpring, value: media.showsLiveActivity)
        .animation(IslandMetrics.softSpring, value: model.peek)
        .animation(IslandMetrics.spring, value: model.hud)
        .animation(IslandMetrics.spring, value: model.clipPeek)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.event)
        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: model.eventExpanded)
        .preferredColorScheme(.dark)
        .onChange(of: model.isDropTargeted) { _, targeted in
            if targeted { model.expand(to: .shelf) }
        }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            compactContent
            if model.expandedContentMounted {
                ExpandedIslandView(model: model, media: media)
                    // Содержимое всегда полного размера: при сворачивании форма его обрезает, а не сжимает,
                    // поэтому карточки (MacBook, погода) не ломаются по ходу анимации.
                    .frame(width: IslandMetrics.expandedWidth,
                           height: model.notchSize.height + IslandMetrics.expandedContentHeight)
                    // Открытие: содержимое опускается вместе с островом и проявляется.
                    // Закрытие — наоборот: остров уходит вверх, а содержимое гаснет, чуть сползая вниз.
                    .opacity(model.isExpanded ? 1 : 0)
                    .offset(y: model.isExpanded ? 0 : 8)
                    .animation(model.isExpanded ? .easeOut(duration: 0.3).delay(0.06) : .easeOut(duration: 0.24),
                               value: model.isExpanded)
                    .allowsHitTesting(model.isExpanded)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -10))
                            .animation(.easeOut(duration: 0.3).delay(0.06)),
                        removal: .identity))
            }
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        if model.isExpanded {
            Color.clear
        } else if let event = model.event, model.eventExpanded {
            EventView(event: event, notchHeight: model.notchSize.height) { model.dismissEvent() }
                .frame(width: event.size.width, height: model.notchSize.height + event.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    if case .notification(let item) = event { openApp(item.bundleID) }
                    if !event.isDevice { model.dismissEvent() }
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.12)),
                    removal: .opacity.animation(.easeIn(duration: 0.14))))
        } else if model.event != nil {
            Color.clear
        } else if let hud = model.hud {
            HUDView(state: hud, notchWidth: model.notchSize.width)
                .transition(.opacity)
        } else if let group = model.clipPeek {
            ClipPeekView(group: group, icon: model.clipboard.icon(for: group.bundleID),
                         notchWidth: model.notchSize.width)
                .id(group.items.first?.id)
                .transition(.opacity)
        } else if media.showsLiveActivity || (model.peek && media.hasTrack) {
            CompactMusicView(media: media, model: model)
                .transition(.opacity.animation(.easeInOut(duration: 0.35)))
        } else {
            Color.clear
        }
    }

    private func openApp(_ bundleID: String) {
        if bundleID == AppNotification.gmailID { return model.gmail.openInbox() }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    model.shelf.add([url])
                    model.tab = .shelf
                }
            }
        }
        return accepted
    }
}
