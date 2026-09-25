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
    @Namespace private var ns

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        VStack(spacing: 0) {
            content
                .frame(width: model.bodySize.width, height: model.bodySize.height, alignment: .top)
                .padding(.horizontal, model.topRadius)
                .background(Color.black)
                .clipShape(shape)
                .overlay {
                    // Подсветка краёв при перетаскивании файла.
                    shape.stroke(Color.white.opacity(model.isDropTargeted ? 0.35 : 0), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(model.isExpanded ? 0.55 : 0), radius: 18, y: 8)
                .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted, perform: handleDrop)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandMetrics.spring, value: model.isExpanded)
        .animation(IslandMetrics.spring, value: media.showsLiveActivity)
        .animation(IslandMetrics.spring, value: model.peek)
        .animation(IslandMetrics.spring, value: model.hud)
        .animation(IslandMetrics.spring, value: model.clipPeek)
        .animation(.spring(response: 0.55, dampingFraction: 0.66), value: model.event)
        .preferredColorScheme(.dark)
        .onChange(of: model.isDropTargeted) { _, targeted in
            if targeted { model.expand(to: .shelf) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedIslandView(model: model, media: media, ns: ns)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(IslandMetrics.spring.delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
        } else if let event = model.event {
            EventView(event: event, notchHeight: model.notchSize.height)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissEvent() }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)).animation(IslandMetrics.spring.delay(0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.15))))
        } else if let hud = model.hud {
            HUDView(state: hud, notchWidth: model.notchSize.width)
                .transition(.opacity.combined(with: .blurReplace))
        } else if let group = model.clipPeek {
            ClipPeekView(group: group, icon: model.clipboard.icon(for: group.bundleID),
                         notchWidth: model.notchSize.width)
                .id(group.items.first?.id)
                .transition(.opacity.combined(with: .blurReplace))
        } else if media.showsLiveActivity || (model.peek && media.hasTrack) {
            CompactMusicView(media: media, model: model, ns: ns)
                .transition(.opacity.combined(with: .blurReplace))
        } else {
            Color.clear
        }
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
