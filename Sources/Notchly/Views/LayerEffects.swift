import AppKit
import SwiftUI

// Бесконечные анимации на Core Animation.
//
// Анимация SwiftUI (TimelineView, repeatForever, symbolEffect) пересчитывается в нашем процессе каждый кадр:
// SwiftUI обновляет граф и заново отрисовывает слой острова целиком — десятки процентов процессора ради
// значка в 22 pt. Здесь та же картинка живёт в отдельном слое AppKit, а движение задаёт CAAnimation:
// её кадры считает WindowServer, приложение в это время спит.
//
// В снапшотах (офскрин-рендер) анимации не применяются — видно исходное состояние.

/// Системный символ с бесконечным пульсом — замена `.symbolEffect(.pulse, options: .repeating.speed(…))`.
/// Прозрачность и период сняты с экрана у системного эффекта: от 1 до 0,3 и обратно за 1,2 / speed секунды.
struct PulsingSymbol: NSViewRepresentable {
    var name: String
    var pointSize: CGFloat
    var weight: NSFont.Weight = .regular
    var multicolor = false
    var speed: Double = 1

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        view.wantsLayer = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)|\(multicolor)|\(speed)"
        guard view.identifier?.rawValue != key else { return }
        view.identifier = NSUserInterfaceItemIdentifier(key)
        var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if multicolor { config = config.applying(.preferringMulticolor()) }
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.3
        pulse.duration = 0.6 / speed
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(pulse, forKey: "pulse")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        nsView.image?.size
    }
}

/// Цвета `color.gradient` так, как их рисует SwiftUI, — для слоёв Core Animation.
/// Формулу SwiftUI не публикует (у белого темнеет низ, у цветных светлеет верх), поэтому один раз
/// рендерим полоску с этим градиентом и берём её пиксели. Кэш по цвету: обложки меняются редко.
@MainActor
enum SwiftUIGradientStops {
    private static var cache: [String: [CGColor]] = [:]
    private static let samples = 33

    /// Сплошной цвет так, как его рисует SwiftUI (для обводок и заливок слоёв).
    static func solid(_ color: Color) -> CGColor {
        let key = "solid " + keyFor(color)
        if let cached = cache[key]?.first { return cached }
        let renderer = ImageRenderer(content: Rectangle().fill(color).frame(width: 1, height: 1))
        renderer.scale = 1
        renderer.colorMode = .extendedLinear
        let result = renderer.cgImage.flatMap { column(of: $0).first } ?? NSColor(color).cgColor
        cache[key] = [result]
        return result
    }

    /// Цвета левого столбца картинки сверху вниз. Рендер идёт в расширенном линейном sRGB: насыщенный верх
    /// градиента выходит за пределы sRGB (на экране P3), и обычный рендер обрезал бы его до 1.
    /// Байты читаем сами: NSBitmapImageRep.colorAt пересчитывает цвет и заметно его разбавляет.
    private static func column(of image: CGImage) -> [CGColor] {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return [] }
        var values = [Float](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGImageByteOrderInfo.order32Little.rawValue
        guard let context = CGContext(data: &values, width: width, height: height, bitsPerComponent: 32,
                                      bytesPerRow: width * 16, space: space, bitmapInfo: info) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // В памяти контекста первая строка — верхняя.
        return (0..<height).compactMap { y in
            let i = y * width * 4
            let a = max(CGFloat(values[i + 3]), 0.0001)
            return CGColor(colorSpace: space, components: [CGFloat(values[i]) / a, CGFloat(values[i + 1]) / a,
                                                           CGFloat(values[i + 2]) / a, a])
        }
    }

    private static func keyFor(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "%.3f %.3f %.3f %.3f", ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    static func colors(for color: Color) -> [CGColor] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        let key = keyFor(color)
        if let cached = cache[key] { return cached }
        let height = 64
        let renderer = ImageRenderer(content: Rectangle().fill(color.gradient).frame(width: 1, height: CGFloat(height)))
        renderer.scale = 1
        renderer.colorMode = .extendedLinear
        var result: [CGColor] = [ns.cgColor, ns.cgColor]
        if let image = renderer.cgImage {
            let pixels = column(of: image)
            if pixels.count == height {
                result = (0..<samples).map { i in
                    pixels[min(height - 1, Int((Double(i) / Double(samples - 1) * Double(height - 1)).rounded()))]
                }
            }
        }
        cache[key] = result
        return result
    }
}

/// Эквалайзер, который «танцует», пока играет музыка. Высоты столбиков — та же формула, что раньше
/// считалась в TimelineView на 30 к/с, но заранее разложенная в ключевые кадры CAKeyframeAnimation:
/// двигает столбики WindowServer, а приложение не просыпается.
struct EqualizerView: NSViewRepresentable {
    var isPlaying: Bool
    var color: Color
    var bars = 4

    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView() }

    func updateNSView(_ view: EqualizerLayerView, context: Context) {
        view.update(bars: bars, colors: SwiftUIGradientStops.colors(for: color), playing: isPlaying)
    }

    static let speeds: [Double] = [5.1, 7.3, 4.2, 6.4, 5.7]
    static let phases: [Double] = [0, 1.7, 3.1, 0.8, 2.4]

    /// Доля высоты столбика в момент t (секунды от эталонной даты), как в прежней версии.
    static func level(bar i: Int, at t: Double) -> Double {
        let wave = abs(sin(t * speeds[i % 5] + phases[i % 5])) * 0.6
            + abs(sin(t * speeds[(i + 2) % 5] * 0.53)) * 0.4
        return 0.22 + 0.78 * wave
    }

    static let pausedLevel = 0.2

    /// Длина петли для столбика: время, за которое обе синусоиды почти точно возвращаются в начало
    /// (у |sin| период π/ω), — чтобы на стыке повторов не было скачка.
    static func loopLength(bar i: Int) -> Double {
        let a = Double.pi / speeds[i % 5]
        let b = Double.pi / (speeds[(i + 2) % 5] * 0.53)
        func miss(_ length: Double, _ period: Double) -> Double {
            let r = (length / period).truncatingRemainder(dividingBy: 1)
            return min(r, 1 - r) * period
        }
        var best = (length: 20.0, error: Double.infinity)
        var length = 12.0
        while length <= 40 {
            let error = miss(length, a) + miss(length, b)
            if error < best.error { best = (length, error) }
            length += 0.005
        }
        return best.length
    }

    final class EqualizerLayerView: NSView {
        private var layers: [CAGradientLayer] = []
        private var playing: Bool?
        private var loops: [Double] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        func update(bars: Int, colors: [CGColor], playing: Bool) {
            if layers.count != bars {
                layers.forEach { $0.removeFromSuperlayer() }
                layers = (0..<bars).map { _ in
                    let bar = CAGradientLayer()
                    bar.masksToBounds = true
                    layer?.addSublayer(bar)
                    return bar
                }
                loops = (0..<bars).map(EqualizerView.loopLength)
                self.playing = nil
                needsLayout = true
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            // Градиент сверху вниз (вид перевёрнут, y смотрит вниз — как у SwiftUI).
            for bar in layers { bar.colors = colors; bar.startPoint = CGPoint(x: 0.5, y: 0); bar.endPoint = CGPoint(x: 0.5, y: 1) }
            CATransaction.commit()
            if self.playing != playing {
                self.playing = playing
                restartAnimations(animated: true)
            }
        }

        override func layout() {
            super.layout()
            if bounds.size != geometryKey { restartAnimations(animated: false) }
        }

        private var geometryKey = CGSize.zero

        /// Раскладывает столбики и заново запускает их движение от текущего момента.
        private func restartAnimations(animated: Bool) {
            guard let playing, !layers.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
            let n = CGFloat(layers.count)
            let spacing = bounds.width * 0.12
            let width = (bounds.width - spacing * (n - 1)) / n
            let height = bounds.height
            let now = Date.timeIntervalSinceReferenceDate
            let mediaNow = CACurrentMediaTime()

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, bar) in layers.enumerated() {
                let presented = bar.presentation()?.bounds.height ?? bar.bounds.height
                bar.cornerRadius = width / 2
                bar.position = CGPoint(x: CGFloat(i) * (width + spacing) + width / 2, y: height / 2)
                let target = CGFloat(playing ? EqualizerView.level(bar: i, at: now) : EqualizerView.pausedLevel) * height
                bar.bounds = CGRect(x: 0, y: 0, width: width, height: target)
                bar.removeAllAnimations()

                // Пауза и продолжение — мягкий переход за 0,3 с, как `.animation(.easeOut(duration: 0.3))`.
                let blend = animated && geometryKey == bounds.size ? 0.3 : 0
                if blend > 0 {
                    let settle = CABasicAnimation(keyPath: "bounds.size.height")
                    settle.fromValue = presented
                    settle.toValue = playing ? CGFloat(EqualizerView.level(bar: i, at: now + blend)) * height : target
                    settle.duration = blend
                    settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bar.add(settle, forKey: "settle")
                }
                guard playing else { continue }
                let loop = loops[i]
                let fps = 60.0
                let count = Int(loop * fps)
                let dance = CAKeyframeAnimation(keyPath: "bounds.size.height")
                dance.values = (0...count).map { k in CGFloat(EqualizerView.level(bar: i, at: Double(k) / fps)) * height }
                dance.calculationMode = .linear
                dance.duration = loop
                dance.repeatCount = .infinity
                // Танец начинается сразу после перехода, с фазой от абсолютного времени, как у прежней версии
                // (формула почти периодична с периодом loop). До начала он не действует — идёт переход.
                dance.beginTime = bar.convertTime(mediaNow, from: nil) + blend
                dance.timeOffset = (now + blend).truncatingRemainder(dividingBy: loop)
                bar.add(dance, forKey: "dance")
            }
            CATransaction.commit()
            geometryKey = bounds.size
        }
    }
}

/// Заливка полосы прогресса трека. Пока трек играет, она равномерно растёт до конца трека —
/// это одна CABasicAnimation, которую ведёт WindowServer; раньше SwiftUI перерисовывал остров
/// каждый кадр ради линейной анимации полосы.
struct TrackProgressFill: NSViewRepresentable {
    /// Доля в момент `date`.
    var fraction: Double
    var date: Date
    /// Доля в секунду (0 — стоит на паузе).
    var rate: Double
    var color: NSColor = .white

    func makeNSView(context: Context) -> FillView { FillView() }

    func updateNSView(_ view: FillView, context: Context) {
        view.update(fraction: fraction, date: date, rate: rate, color: color)
    }

    final class FillView: NSView {
        private let fill = CALayer()
        private var state: (fraction: Double, date: Date, rate: Double)?
        private var animatedWidth: CGFloat = -1

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            layer?.addSublayer(fill)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(fraction: Double, date: Date, rate: Double, color: NSColor) {
            fill.backgroundColor = color.cgColor
            if let state, state.fraction == fraction, state.date == date, state.rate == rate { return }
            state = (fraction, date, rate)
            restart()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.position = CGPoint(x: 0, y: bounds.midY)
            fill.cornerRadius = bounds.height / 2
            fill.bounds.size.height = bounds.height
            CATransaction.commit()
            if bounds.width != animatedWidth { restart() }
        }

        private func restart() {
            guard let state, bounds.width > 0 else { return }
            animatedWidth = bounds.width
            let now = Date()
            let current = min(max(state.fraction + state.rate * now.timeIntervalSince(state.date), 0), 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.removeAnimation(forKey: "progress")
            fill.bounds.size.width = bounds.width * current
            if state.rate > 0, current < 1 {
                let grow = CABasicAnimation(keyPath: "bounds.size.width")
                grow.fromValue = bounds.width * current
                grow.toValue = bounds.width
                grow.duration = (1 - current) / state.rate
                grow.timingFunction = CAMediaTimingFunction(name: .linear)
                // Слой хранит текущее значение (его видят снапшоты), а после конца трека полоса остаётся полной.
                grow.fillMode = .forwards
                grow.isRemovedOnCompletion = false
                fill.add(grow, forKey: "progress")
            }
            CATransaction.commit()
        }
    }
}

/// Моменты, когда позиция трека переходит через целую секунду: подписи времени обновляются ровно тогда.
struct TrackSecondsSchedule: TimelineSchedule {
    var elapsed: Double
    var timestamp: Date
    var playing: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard playing else { return AnyIterator([startDate].makeIterator()) }
        // Позиция в startDate и ближайшая следующая целая секунда.
        let position = elapsed + startDate.timeIntervalSince(timestamp)
        var next = startDate.addingTimeInterval(position.rounded(.up) - position)
        var first = true
        return AnyIterator {
            if first { first = false; return startDate }
            defer { next = next.addingTimeInterval(1) }
            return next
        }
    }
}

/// Дуга прогресса таймера: `Circle().trim(0, progress).stroke(...)`, начало сверху, по часовой стрелке.
/// Пока таймер идёт, дуга растёт сама (CABasicAnimation до конца отсчёта), а не раз в секунду
/// с секундной линейной анимацией SwiftUI, которая перерисовывала остров непрерывно.
struct CountdownArc: NSViewRepresentable {
    var progress: Double
    /// Прирост доли в секунду (0 — на паузе или не запущен).
    var rate: Double
    var tint: Color
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.update(progress: progress, rate: rate, color: SwiftUIGradientStops.solid(tint), lineWidth: lineWidth)
    }

    final class ArcView: NSView {
        private let arc = CAShapeLayer()
        private var state: (progress: Double, rate: Double, at: Date)?
        private var pathSize = CGSize.zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            arc.fillColor = nil
            arc.lineCap = .round
            layer?.addSublayer(arc)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(progress: Double, rate: Double, color: CGColor, lineWidth: CGFloat) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.strokeColor = color
            arc.lineWidth = lineWidth
            CATransaction.commit()
            // Та же линия, если прогресс просто продолжился по прежнему темпу: не перезапускаем анимацию.
            if let state, state.rate == rate, rate > 0,
               abs(state.progress + rate * Date().timeIntervalSince(state.at) - progress) < 0.002 { return }
            if let state, state.rate == 0, rate == 0, state.progress == progress { return }
            state = (progress, rate, Date())
            restart()
        }

        override func layout() {
            super.layout()
            guard bounds.size != pathSize else { return }
            pathSize = bounds.size
            let radius = min(bounds.width, bounds.height) / 2
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = CGMutablePath()
            // Слой не перевёрнут (y вверх): сверху — угол π/2, по часовой — углы убывают.
            path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            arc.path = path
            CATransaction.commit()
            restart()
        }

        private func restart() {
            guard let state, pathSize != .zero else { return }
            let current = min(max(state.progress + state.rate * Date().timeIntervalSince(state.at), 0), 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.removeAnimation(forKey: "progress")
            arc.strokeEnd = current
            if state.rate > 0, current < 1 {
                let grow = CABasicAnimation(keyPath: "strokeEnd")
                grow.fromValue = current
                grow.toValue = 1
                grow.duration = (1 - current) / state.rate
                grow.timingFunction = CAMediaTimingFunction(name: .linear)
                // Слой хранит текущее значение (его видят снапшоты), а в конце отсчёта дуга остаётся полной.
                grow.fillMode = .forwards
                grow.isRemovedOnCompletion = false
                arc.add(grow, forKey: "progress")
            }
            CATransaction.commit()
        }
    }
}

/// Заливка батарейки. При появлении она плавно дорастает от нуля до заряда, по ней пробегает блик,
/// а во время зарядки блик повторяется каждые несколько секунд — как на iPhone.
/// Раньше то же делал SwiftUI: полторы секунды заливки заставляли пересчитывать остров каждый кадр
/// открытия (~55 мс процессора на открытие). Здесь рост и блик — CAAnimation, их кадры считает WindowServer.
struct BatteryFillLayer: NSViewRepresentable {
    var percent: Int
    var charging: Bool
    var color: Color
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> FillView { FillView() }

    func updateNSView(_ view: FillView, context: Context) {
        view.update(fraction: CGFloat(min(max(percent, 0), 100)) / 100, charging: charging,
                    color: SwiftUIGradientStops.solid(color), cornerRadius: cornerRadius)
    }

    final class FillView: NSView {
        private let fill = CALayer()
        private let gloss = CAGradientLayer()
        private let shine = CAGradientLayer()
        private var fraction: CGFloat?
        private var charging = false
        private var color: CGColor?
        /// Заливка ещё не показывалась: рост от нуля начнётся, когда вид окажется в окне и получит размер.
        private var pendingAppear = true
        private var laidOutSize = CGSize.zero

        /// Длительности — как у прежней анимации SwiftUI (`.smooth(duration: 1.2).delay(0.2)`).
        private static let growDelay = 0.2
        private static let growDuration = 1.2
        private static let sweepDuration = 1.1
        /// Период повтора блика во время зарядки (пробег + пауза).
        private static let chargingPeriod = 2.8

        private var animates: Bool {
            !SnapshotFlags.isRendering && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.masksToBounds = true
            layer?.addSublayer(fill)

            // Стеклянный отсвет сверху — статичный, ничего не стоит.
            gloss.colors = [NSColor.white.withAlphaComponent(0.32).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            gloss.startPoint = CGPoint(x: 0.5, y: 1)
            gloss.endPoint = CGPoint(x: 0.5, y: 0.45)
            fill.addSublayer(gloss)

            // Блик — узкая светлая полоса, которую анимация проносит слева направо; видна только внутри заливки.
            let clear = NSColor.white.withAlphaComponent(0).cgColor
            shine.colors = [clear, NSColor.white.withAlphaComponent(0.75).cgColor, clear]
            shine.locations = [0, 0.5, 1]
            shine.startPoint = CGPoint(x: 0, y: 0.5)
            shine.endPoint = CGPoint(x: 1, y: 0.5)
            shine.opacity = 0
            fill.addSublayer(shine)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(fraction: CGFloat, charging: Bool, color: CGColor, cornerRadius: CGFloat) {
            // updateNSView зовётся на каждом кадре открытия острова — без изменений ничего не делаем.
            let colorChanged = self.color.map { $0 != color } ?? true
            if self.fraction == fraction, self.charging == charging, !colorChanged, fill.cornerRadius == cornerRadius { return }

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            fill.backgroundColor = color
            CATransaction.commit()
            self.color = color

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.cornerRadius = cornerRadius
            CATransaction.commit()

            let oldFraction = self.fraction
            let chargingChanged = self.charging != charging
            self.fraction = fraction
            self.charging = charging

            if pendingAppear {
                startAppearIfReady()
            } else {
                if let oldFraction, oldFraction != fraction { setWidth(animatedFrom: currentWidth, duration: 1.0, delay: 0) }
                if chargingChanged { restartShine(delay: 0) }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Вид убрали с экрана — в следующий раз заливка снова вырастет от нуля.
                pendingAppear = true
                fill.removeAllAnimations()
                shine.removeAllAnimations()
            } else {
                startAppearIfReady()
            }
        }

        override func layout() {
            super.layout()
            guard bounds.size != laidOutSize else { return }
            laidOutSize = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.position = CGPoint(x: 0, y: bounds.midY)
            fill.bounds.size.height = bounds.height
            gloss.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            let band = max(bounds.height * 1.6, 8)
            shine.bounds = CGRect(x: 0, y: 0, width: band, height: bounds.height)
            shine.position = CGPoint(x: -band, y: bounds.height / 2)
            CATransaction.commit()
            if pendingAppear {
                startAppearIfReady()
            } else {
                setWidth(animatedFrom: nil, duration: 0, delay: 0)
                restartShine(delay: 0)
            }
        }

        private var targetWidth: CGFloat { max(2, bounds.width * (fraction ?? 0)) }
        private var currentWidth: CGFloat { fill.presentation()?.bounds.width ?? fill.bounds.width }

        private func startAppearIfReady() {
            guard pendingAppear, window != nil, fraction != nil, bounds.width > 0 else { return }
            pendingAppear = false
            guard animates else {
                setWidth(animatedFrom: nil, duration: 0, delay: 0)
                restartShine(delay: 0)
                return
            }
            setWidth(animatedFrom: 2, duration: Self.growDuration, delay: Self.growDelay)
            // Первый блик — когда заливка почти доросла.
            restartShine(delay: Self.growDelay + Self.growDuration * 0.55, onAppear: true)
        }

        /// Ставит итоговую ширину в модель слоя (её видят снапшоты) и, если нужно, анимирует к ней.
        private func setWidth(animatedFrom start: CGFloat?, duration: Double, delay: Double) {
            let target = targetWidth
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.removeAnimation(forKey: "grow")
            fill.bounds.size.width = target
            if let start, duration > 0, animates, abs(start - target) > 0.5 {
                let grow = CABasicAnimation(keyPath: "bounds.size.width")
                grow.fromValue = start
                grow.toValue = target
                grow.duration = duration
                grow.beginTime = fill.convertTime(CACurrentMediaTime(), from: nil) + delay
                grow.fillMode = .backwards
                // Кривая, близкая к `.smooth` у SwiftUI: быстрый старт и долгое мягкое торможение.
                grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                fill.add(grow, forKey: "grow")
            }
            CATransaction.commit()
        }

        /// Блик: один пробег при появлении, а во время зарядки — бесконечный повтор с паузой.
        private func restartShine(delay: Double, onAppear: Bool = false) {
            shine.removeAnimation(forKey: "sweep")
            guard animates, bounds.width > 0, onAppear || charging else { return }
            let band = shine.bounds.width
            let run = CABasicAnimation(keyPath: "position.x")
            run.fromValue = -band / 2
            run.toValue = bounds.width + band / 2
            run.duration = Self.sweepDuration
            run.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let glow = CAKeyframeAnimation(keyPath: "opacity")
            glow.values = [0, 1, 1, 0]
            glow.keyTimes = [0, 0.2, 0.75, 1]
            glow.duration = Self.sweepDuration

            let sweep = CAAnimationGroup()
            sweep.animations = [run, glow]
            sweep.beginTime = shine.convertTime(CACurrentMediaTime(), from: nil) + delay
            sweep.duration = charging ? Self.chargingPeriod : Self.sweepDuration
            sweep.repeatCount = charging ? .infinity : 1
            shine.add(sweep, forKey: "sweep")
        }
    }
}
