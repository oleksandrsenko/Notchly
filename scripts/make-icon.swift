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

    // Монохромный фон: мягкий светло-серый градиент.
    NSGradient(colors: [color(0xfbfbfd), color(0xe4e4e9), color(0xcfcfd6)],
               atLocations: [0, 0.6, 1], colorSpace: .sRGB)!.draw(in: tile, angle: 90)

    // Сам «остров» — чёрная капсула с мягкой тенью.
    let pill = NSBezierPath(roundedRect: NSRect(x: 222, y: 400, width: 580, height: 176), xRadius: 88, yRadius: 88)
    NSGraphicsContext.saveGraphicsState()
    let pillShadow = NSShadow()
    pillShadow.shadowColor = .black.withAlphaComponent(0.35)
    pillShadow.shadowBlurRadius = 36
    pillShadow.shadowOffset = NSSize(width: 0, height: 20)
    pillShadow.set()
    color(0x000000).setFill()
    pill.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Едва заметный блик по верхней кромке капсулы.
    NSGraphicsContext.saveGraphicsState()
    pill.addClip()
    NSGradient(colors: [color(0xffffff, 0.10), color(0xffffff, 0)])!
        .draw(in: NSRect(x: 222, y: 400, width: 580, height: 60), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Глазок камеры справа.
    let lens = NSRect(x: 690, y: 456, width: 64, height: 64)
    NSGradient(colors: [color(0x2a2a2e), color(0x0b0b0d)])!.draw(in: NSBezierPath(ovalIn: lens), angle: -90)
    NSGradient(colors: [color(0x3a3a40), color(0x121214)])!
        .draw(in: NSBezierPath(ovalIn: lens.insetBy(dx: 16, dy: 16)), angle: -90)
    color(0xffffff, 0.35).setFill()
    NSBezierPath(ovalIn: NSRect(x: lens.minX + 22, y: lens.minY + 20, width: 9, height: 9)).fill()

    NSGraphicsContext.restoreGraphicsState()

    // Тонкая светлая кромка.
    color(0x000000, 0.08).setStroke()
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
