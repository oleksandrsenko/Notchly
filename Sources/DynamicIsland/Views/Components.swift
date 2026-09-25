import SwiftUI

/// Обложка с плавной сменой картинки и заглушкой, когда обложки нет.
struct ArtworkView: View {
    var image: NSImage?
    var accent: Color
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.15)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 200, weight: .semibold))
                        .minimumScaleFactor(0.01)
                        .padding(cornerRadius * 1.2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.12)),
                        removal: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Эквалайзер, который «танцует», пока играет музыка.
struct EqualizerView: View {
    var isPlaying: Bool
    var color: Color
    var bars = 4

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.4, 5.7]
    private let phases: [Double] = [0, 1.7, 3.1, 0.8, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<bars, id: \.self) { i in
                        let wave = abs(sin(t * speeds[i % 5] + phases[i % 5])) * 0.6
                            + abs(sin(t * speeds[(i + 2) % 5] * 0.53)) * 0.4
                        Capsule()
                            .fill(color.gradient)
                            .frame(height: geo.size.height * (isPlaying ? 0.22 + 0.78 * wave : 0.2))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isPlaying)
    }
}

/// Кнопка-иконка с подсветкой при наведении и «проседанием» при нажатии.
struct IconButton: View {
    var systemName: String
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var padding: CGFloat = 8
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + padding * 2, height: size + padding * 2)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Горизонтальный слайдер в стиле Пункта управления.
struct CapsuleSlider: View {
    var value: Double
    var icon: String
    var tint: Color = .white
    var height: CGFloat = 40
    var iconAction: (() -> Void)?
    var onChange: (Double) -> Void

    @ViewState private var dragValue: Double?
    @ViewState private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(hovering ? 0.16 : 0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * shown))
                    .opacity(shown > 0.001 ? 1 : 0.0)
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(shown > 0.08 ? Color.black : Color.white)
                        .frame(width: height, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { iconAction?() }
                    Spacer()
                    Text("\(Int((shown * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(shown > 0.9 ? .black.opacity(0.7) : .white.opacity(0.7))
                        .padding(.trailing, 14)
                        .contentTransition(.numericText())
                }
            }
            .clipShape(Capsule())
            .scaleEffect(dragValue != nil ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragValue != nil)
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let v = min(max(g.location.x / geo.size.width, 0), 1)
                    dragValue = v
                    onChange(v)
                }
                .onEnded { _ in dragValue = nil })
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        }
        .frame(height: height)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

/// Аналог `@State`. В macOS 27 SDK `@State` стал макросом, а его плагин есть только
/// в полном Xcode, поэтому с Command Line Tools используем обычную обёртку над `State`.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
