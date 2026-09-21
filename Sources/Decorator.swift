import AppKit
import CoreText

// MARK: - 导出装饰
//
// 水印与装饰边框只作用于**导出结果**，屏幕上的标注画布不受影响 ——
// 否则用户会在标注时看到一个自己没画的边框，还会污染撤销历史。
// 所有导出路径都经过 Exporter.currentImage()，装饰就挂在那一个点上。

enum FrameStyle: String, CaseIterable {
    case none, border, shadow, torn

    var title: String {
        switch self {
        case .none:   return LS("Ohne", "None", "无边框", "無邊框")
        case .border: return LS("Rahmen", "Border", "描边", "描邊")
        case .shadow: return LS("Schatten", "Drop shadow", "阴影", "陰影")
        case .torn:   return LS("Gerissene Kante", "Torn edge", "撕边", "撕邊")
        }
    }
}

enum Decorator {

    /// 按当前设置给导出图加装饰与水印。
    /// 两者都没开时**原样返回**，不做任何多余的重绘（避免无谓的重新编码损失）。
    static func apply(_ src: CGImage) -> CGImage {
        let style = FrameStyle(rawValue: Prefs.frameStyle) ?? .none
        let watermark = Prefs.watermark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard style != .none || !watermark.isEmpty else { return src }

        let pad: CGFloat
        switch style {
        case .none:   pad = watermark.isEmpty ? 0 : 0
        case .border: pad = 14
        case .shadow: pad = 38      // 要给阴影留出模糊半径
        case .torn:   pad = 16
        }

        let pw = src.width + Int(pad * 2)
        let ph = src.height + Int(pad * 2)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return src }
        ctx.interpolationQuality = .high
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))

        let imgRect = CGRect(x: pad, y: pad, width: CGFloat(src.width), height: CGFloat(src.height))

        switch style {
        case .shadow:
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 20,
                          color: NSColor.black.withAlphaComponent(0.38).cgColor)
            ctx.draw(src, in: imgRect)
            ctx.restoreGState()

        case .torn:
            ctx.saveGState()
            ctx.addPath(tornPath(in: imgRect))
            ctx.clip()
            ctx.draw(src, in: imgRect)
            ctx.restoreGState()

        case .border:
            ctx.draw(src, in: imgRect)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(imgRect.insetBy(dx: -1, dy: -1))

        case .none:
            ctx.draw(src, in: imgRect)
        }

        if !watermark.isEmpty {
            drawWatermark(ctx, text: watermark,
                          canvas: CGRect(x: 0, y: 0, width: pw, height: ph),
                          image: imgRect)
        }
        return ctx.makeImage() ?? src
    }

    /// 撕裂边缘。用固定种子的伪随机数，保证同一张图每次导出结果一致
    /// （否则用户会看到"同样的操作，每次撕出来的边都不一样"）。
    private static func tornPath(in r: CGRect) -> CGPath {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func rnd() -> CGFloat {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return CGFloat(seed % 1000) / 1000.0
        }
        let jag: CGFloat = 9
        let step: CGFloat = 13
        let p = CGMutablePath()

        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        var x = r.minX
        while x < r.maxX {
            x = min(r.maxX, x + step)
            p.addLine(to: CGPoint(x: x, y: r.maxY - rnd() * jag))
        }
        var y = r.maxY
        while y > r.minY {
            y = max(r.minY, y - step)
            p.addLine(to: CGPoint(x: r.maxX - rnd() * jag, y: y))
        }
        x = r.maxX
        while x > r.minX {
            x = max(r.minX, x - step)
            p.addLine(to: CGPoint(x: x, y: r.minY + rnd() * jag))
        }
        y = r.minY
        while y < r.maxY {
            y = min(r.maxY, y + step)
            p.addLine(to: CGPoint(x: r.minX + rnd() * jag, y: y))
        }
        p.closeSubpath()
        return p
    }

    /// 右下角水印。白色文字 + 深色描边，深浅底图上都读得清。
    private static func drawWatermark(_ ctx: CGContext, text: String, canvas: CGRect, image: CGRect) {
        let fontSize = max(13, min(canvas.width, canvas.height) * 0.026)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .shadow: shadow
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let inset: CGFloat = 16

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: canvas.maxX - inset - width, y: canvas.minY + inset + descent)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
