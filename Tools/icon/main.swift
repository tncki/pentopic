// icon/main.swift — 生成 AppIcon.icns（屏幕 + 荧光笔 + 红箭头 + 绿勾）
import AppKit

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tools/icon
    .deletingLastPathComponent()   // Tools
    .deletingLastPathComponent()   // 项目根
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)

    // 背景圆角方块（macOS 风格留边）
    let inset = s * 0.055
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2),
                          xRadius: s * 0.225, yRadius: s * 0.225)
    let grad = NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.29, blue: 0.58, alpha: 1),
                                   NSColor(srgbRed: 0.07, green: 0.13, blue: 0.30, alpha: 1)])!
    grad.draw(in: bg, angle: -90)

    // 屏幕白板
    let screen = NSRect(x: s * 0.185, y: s * 0.225, width: s * 0.63, height: s * 0.55)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: s * 0.045, yRadius: s * 0.045)
    NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1).setFill()
    screenPath.fill()

    // 屏幕里的内容（模拟被标注的文档）
    NSColor(srgbRed: 0.72, green: 0.78, blue: 0.88, alpha: 1).setFill()
    for i in 0..<3 {
        let w = screen.width * (i == 2 ? 0.42 : 0.66)
        NSBezierPath(roundedRect: NSRect(x: screen.minX + s * 0.06,
                                         y: screen.maxY - s * 0.14 - CGFloat(i) * s * 0.085,
                                         width: w, height: s * 0.035),
                     xRadius: s * 0.017, yRadius: s * 0.017).fill()
    }

    // 荧光笔笔迹（黄色马克）
    let marker = NSBezierPath(roundedRect: NSRect(x: screen.minX + s * 0.055,
                                                  y: screen.minY + s * 0.105,
                                                  width: screen.width * 0.72, height: s * 0.075),
                              xRadius: s * 0.037, yRadius: s * 0.037)
    NSColor(srgbRed: 1.0, green: 0.83, blue: 0.05, alpha: 0.92).setFill()
    marker.fill()

    // 红色箭头
    let arrow = NSBezierPath()
    arrow.lineWidth = s * 0.045
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: s * 0.80, y: s * 0.80))
    arrow.line(to: NSPoint(x: s * 0.60, y: s * 0.50))
    NSColor(srgbRed: 0.88, green: 0.10, blue: 0.12, alpha: 1).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: s * 0.585, y: s * 0.475))
    head.line(to: NSPoint(x: s * 0.60, y: s * 0.60))
    head.line(to: NSPoint(x: s * 0.695, y: s * 0.545))
    head.close()
    NSColor(srgbRed: 0.88, green: 0.10, blue: 0.12, alpha: 1).setFill()
    head.fill()

    // 绿色对勾
    let check = NSBezierPath()
    check.lineWidth = s * 0.055
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: s * 0.235, y: s * 0.325))
    check.line(to: NSPoint(x: s * 0.315, y: s * 0.245))
    check.line(to: NSPoint(x: s * 0.455, y: s * 0.395))
    NSColor(srgbRed: 0.10, green: 0.66, blue: 0.16, alpha: 1).setStroke()
    check.stroke()

    img.unlockFocus()
    return img
}

func png(_ size: CGFloat, _ px: Int) -> Data? {
    let img = drawIcon(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, px) in entries {
    if let d = png(CGFloat(px), px) {
        try? d.write(to: iconset.appendingPathComponent(name))
    }
}
print("iconset geschrieben: \(iconset.path)")
exit(0)
