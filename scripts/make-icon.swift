#!/usr/bin/env swift
// Рисует иконку Notchly и собирает Resources/AppIcon.icns.
// Запуск: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let side: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: NSRect, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
    // Координаты перевёрнуты (y вниз): «верх» — minY.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: rect.minX + top, y: rect.minY))
    p.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
    p.curve(to: NSPoint(x: rect.maxX, y: rect.minY + top), controlPoint1: NSPoint(x: rect.maxX, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY))
    p.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottom))
    p.curve(to: NSPoint(x: rect.maxX - bottom, y: rect.maxY), controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY))
    p.line(to: NSPoint(x: rect.minX + bottom, y: rect.maxY))
    p.curve(to: NSPoint(x: rect.minX, y: rect.maxY - bottom), controlPoint1: NSPoint(x: rect.minX, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY))
    p.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
    p.curve(to: NSPoint(x: rect.minX + top, y: rect.minY), controlPoint1: NSPoint(x: rect.minX, y: rect.minY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.minY))
    p.close()
    return p
}

let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    // Тень всей иконки, как у системных.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: 10)   // в перевёрнутых координатах «+» — вниз
    shadow.set()
    color(0x101218).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Обои экрана.
    NSGradient(colors: [color(0x2b3f94), color(0x6a44aa), color(0x160f33)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: tile, angle: -55)
    // Мягкие цветные пятна.
    for (center, hex, radius) in [(NSPoint(x: 260, y: 820), UInt32(0xff5fa2), CGFloat(360)),
                                  (NSPoint(x: 820, y: 640), UInt32(0x4fd1ff), CGFloat(300))] {
        NSGradient(colors: [color(hex, 0.45), color(hex, 0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    // Чёрная рамка экрана сверху.
    color(0x000000).setFill()
    NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: 64).fill()

    // Остров, свисающий из выреза, — с мягкой тенью.
    let island = roundedRect(NSRect(x: 232, y: 100, width: 560, height: 318), top: 0, bottom: 128)
    NSGraphicsContext.saveGraphicsState()
    let islandShadow = NSShadow()
    islandShadow.shadowColor = .black.withAlphaComponent(0.55)
    islandShadow.shadowBlurRadius = 40
    islandShadow.shadowOffset = NSSize(width: 0, height: 18)
    islandShadow.set()
    color(0x000000).setFill()
    island.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Обложка.
    let art = NSBezierPath(roundedRect: NSRect(x: 300, y: 176, width: 148, height: 148), xRadius: 34, yRadius: 34)
    NSGradient(colors: [color(0xff9f43), color(0xff4f8b), color(0x9b5cff)])!.draw(in: art, angle: -45)

    // Эквалайзер.
    let bars: [CGFloat] = [70, 128, 92, 150, 104]
    for (i, h) in bars.enumerated() {
        let x = 492 + CGFloat(i) * 48
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 324 - h, width: 28, height: h), xRadius: 14, yRadius: 14)
        color(0xffffff).setFill()
        bar.fill()
    }

    // Полоса прогресса.
    NSBezierPath(roundedRect: NSRect(x: 300, y: 356, width: 424, height: 14), xRadius: 7, yRadius: 7).addClip()
    color(0xffffff, 0.22).setFill()
    NSRect(x: 300, y: 356, width: 424, height: 14).fill()
    color(0xffffff, 0.9).setFill()
    NSRect(x: 300, y: 356, width: 250, height: 14).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Тонкая светлая кромка.
    color(0xffffff, 0.08).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
    return true
}

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: root.appendingPathComponent("docs/icon.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Готово: \(out.path)" : "iconutil завершился с ошибкой")
