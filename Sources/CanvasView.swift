// CanvasView.swift — 每块屏幕的画布状态 + 绘制视图（全部绘图工具）
import AppKit

// MARK: - 画布状态（每块屏幕一份）

final class CanvasState {
    let screen: NSScreen
    let pointSize: CGSize
    let scale: CGFloat
    let frozenCG: CGImage?
    let frozenImage: NSImage?
    let layer: AnnotationLayer

    var strokes: [Stroke] = []
    /// 已撤销的笔画（用于重做）。任何新笔画都会清空它 —— 这是撤销栈的标准语义。
    var undoneStrokes: [Stroke] = []
    var region: CGRect?
    var background: BackgroundKind = .currentScreen
    var clipboardCG: CGImage?
    var clipboardSize: CGSize = .zero

    var zoom: CGFloat = 1
    var zoomCenter: CGPoint
    var showCrosshair = false
    var composedCache: CGImage?

    var isZoomed: Bool { zoom > 1.0001 }

    init?(screen: NSScreen, captured: CapturedScreen?) {
        self.screen = screen
        self.pointSize = screen.frame.size
        self.scale = screen.backingScaleFactor
        self.frozenCG = captured?.cgImage
        if let c = captured {
            self.frozenImage = NSImage(cgImage: c.cgImage, size: c.pointSize)
        } else {
            self.frozenImage = nil
        }
        let pw = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        let ph = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        guard let l = AnnotationLayer(pixelWidth: pw, pixelHeight: ph, scale: screen.backingScaleFactor) else { return nil }
        self.layer = l
        self.zoomCenter = CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)

        // 打码要读底图。用闭包而不是快照 —— 底图会随「空白纸 / 剪贴板」变化。
        l.backgroundProvider = { [weak self] in self?.currentBackgroundCG() }
        l.backgroundScale = screen.backingScaleFactor
    }

    /// 下一个序号。直接从已有笔画推导 —— 这样撤销/重做后编号自动正确，
    /// 不需要额外维护一个会和历史脱节的计数器。
    var nextNumber: Int {
        strokes.reduce(1) { acc, s in
            if case .number = s.shape { return acc + 1 }
            return acc
        }
    }

    /// 可供打码读取的底图。空白纸/方格纸这类没有"底下的内容"，返回 nil。
    func currentBackgroundCG() -> CGImage? {
        switch background {
        case .currentScreen: return frozenCG
        case .clipboard:     return clipboardCG ?? frozenCG
        default:             return nil
        }
    }

    var bounds: CGRect { CGRect(origin: .zero, size: pointSize) }

    /// 导出/打印/复制用的合成图（背景 + 标注），按区域裁剪
    func composeCG(region: CGRect? = nil) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let pw = Int((pointSize.width * scale).rounded())
        let ph = Int((pointSize.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: pointSize.height)
        ctx.scaleBy(x: 1, y: -1)
        CanvasRenderer.drawBackground(self, in: ctx)
        if let layerImg = layer.snapshot() {
            CanvasRenderer.drawFullImage(ctx, layerImg, size: pointSize)
        }
        guard let full = ctx.makeImage() else { return nil }
        guard let r = region else { return full }
        let crop = CGRect(x: r.minX * scale, y: r.minY * scale,
                          width: r.width * scale, height: r.height * scale).integral
        return full.cropping(to: crop) ?? full
    }

    /// 缩放视图里显示的源图（背景 + 标注），带缓存
    func zoomSource() -> CGImage? {
        if let c = composedCache { return c }
        let c = composeCG(region: nil)
        composedCache = c
        return c
    }
    func invalidateZoomCache() { composedCache = nil }

    func rebuild() { layer.rebuild(from: strokes) }

    var visibleSourceRect: CGRect {
        let w = pointSize.width / zoom, h = pointSize.height / zoom
        var x = zoomCenter.x - w / 2, y = zoomCenter.y - h / 2
        x = min(max(0, x), max(0, pointSize.width - w))
        y = min(max(0, y), max(0, pointSize.height - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - 背景渲染（视图与导出共用）

enum CanvasRenderer {

    static func drawBackground(_ st: CanvasState, in ctx: CGContext) {
        let r = st.bounds
        switch st.background {
        case .currentScreen:
            if let cg = st.frozenCG {
                drawFullImage(ctx, cg, size: st.pointSize)
            } else {
                ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
            }
        case .white:
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
        case .black:
            ctx.setFillColor(NSColor.black.cgColor); ctx.fill(r)
        case .grid:
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
            ctx.setStrokeColor(NSColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            let step: CGFloat = 24
            var x: CGFloat = 0
            while x <= r.width { ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: r.height)); ctx.strokePath(); x += step }
            var y: CGFloat = 0
            while y <= r.height { ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: r.width, y: y)); ctx.strokePath(); y += step }
        case .dots:
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
            ctx.setFillColor(NSColor(srgbRed: 0.65, green: 0.72, blue: 0.82, alpha: 1).cgColor)
            let step: CGFloat = 24
            var y: CGFloat = step
            while y <= r.height {
                var x: CGFloat = step
                while x <= r.width {
                    ctx.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                    x += step
                }
                y += step
            }
        case .lines:
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
            ctx.setStrokeColor(NSColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            var y: CGFloat = 28
            while y <= r.height {
                ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: r.width, y: y)); ctx.strokePath()
                y += 28
            }
        case .clipboard:
            ctx.setFillColor(NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1).cgColor); ctx.fill(r)
            if let cg = st.clipboardCG {
                drawFullImage(ctx, cg, size: st.clipboardSize)
            }
        }
    }

    /// 在 y 轴向下的上下文里正向绘制一张铺满画布的位图
    static func drawFullImage(_ ctx: CGContext, _ img: CGImage, size: CGSize) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
    }
}

// MARK: - 取色

enum PixelSampler {
    static func color(of image: CGImage, at pixel: CGPoint) -> NSColor? {
        let x = Int(pixel.x.rounded(.down)), y = Int(pixel.y.rounded(.down))
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        // 先裁出 1×1：cropping 是惰性的，避免把整张 3K 图绘制进 1×1 上下文（原来每次鼠标移动都这么干）
        guard let one = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var px: [UInt8] = [0, 0, 0, 0]
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                       blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}

// MARK: - 文本编辑框

final class CanvasTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?(); return                                   // ESC
        case 36, 76:                                                   // Enter
            let m = event.modifierFlags
            // 原版用 Ctrl+Enter 插入换行，这里同时接受 ⌥/⇧/⌘
            if m.contains(.option) || m.contains(.shift) || m.contains(.command) || m.contains(.control) {
                insertNewline(nil); return
            }
            onCommit?(); return
        default: break
        }
        super.keyDown(with: event)
    }
}

final class TextEditBox: NSView, NSTextViewDelegate {
    let tv = CanvasTextView()
    let fontSize: CGFloat
    var onCommit: ((String, CGPoint, CGFloat) -> Void)?
    var onCancel: (() -> Void)?
    private var dragOrigin: NSPoint?

    init(origin: CGPoint, fontSize: CGFloat, color: NSColor, initial: String = "") {
        self.fontSize = fontSize
        let h = fontSize * 1.4 + 20
        super.init(frame: NSRect(x: origin.x, y: origin.y, width: max(140, fontSize * 6), height: h))
        wantsLayer = true

        tv.frame = NSRect(x: 6, y: 12, width: bounds.width - 12, height: bounds.height - 18)
        tv.autoresizingMask = [.width, .height]
        tv.isRichText = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        tv.textColor = color
        tv.insertionPointColor = color
        tv.delegate = self
        tv.string = initial
        tv.onCommit = { [weak self] in self?.commit() }
        tv.onCancel = { [weak self] in self?.cancel() }
        addSubview(tv)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 0.55).setFill()
        bounds.fill()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.white.setStroke()
        p.stroke()
    }

    func beginEditing() {
        window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
    }

    func textDidChange(_ notification: Notification) {
        resizeToFit()
    }

    private func resizeToFit() {
        let lines = tv.string.components(separatedBy: "\n")
        let size = ShapeRenderer.textSize(tv.string.isEmpty ? " " : tv.string, fontSize: fontSize)
        let w = max(140, size.width + 28)
        let h = fontSize * 1.4 * CGFloat(max(1, lines.count)) + 22
        var f = frame
        f.size = NSSize(width: w, height: h)
        frame = f
        tv.frame = NSRect(x: 6, y: 12, width: w - 12, height: h - 18)
    }

    private func commit() {
        let s = tv.string
        onCommit?(s, frame.origin, fontSize)
        removeFromSuperview()
    }

    private func cancel() {
        onCancel?()
        removeFromSuperview()
    }

    // 拖动标题条移动文本框
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y <= 12 {
            dragOrigin = p
        } else {
            super.mouseDown(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let o = dragOrigin else { return }
        let p = convert(event.locationInWindow, from: nil)
        var f = frame
        f.origin.x += p.x - o.x
        f.origin.y += p.y - o.y
        frame = f
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }
}

// MARK: - 画布视图

final class CanvasView: NSView {

    let state: CanvasState
    weak var controller: SessionController?

    private var live: Stroke?
    private var livePoints: [CGPoint] = []
    private var dragStart: CGPoint = .zero
    private var dragCurrent: CGPoint = .zero
    private var mousePoint: CGPoint = .zero
    private var hasMouse = false
    private var tracking: NSTrackingArea?
    private var editBox: TextEditBox?

    private var regionDragStart: CGPoint?
    private var regionMoveOffset: CGPoint?

    private var lastPan: CGPoint?
    /// 本次拖动是否被拒绝（例如空白纸上打码）。mouseDown 里 return 只能挡住"按下"，
    /// 后面的 mouseDragged / mouseUp 照样会跑，所以需要一个标记贯穿整次拖动。
    private var dragRejected = false
    /// 是否正在拖动。ESC 需要据此决定"取消这次拖动"还是"结束标注"。
    private(set) var isDragging = false

    init(state: CanvasState, controller: SessionController) {
        self.state = state
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: state.pointSize))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    var hasMousePoint: Bool { hasMouse }
    var mousePointValue: CGPoint { mousePoint }

    func refreshCursor() {
        window?.invalidateCursorRects(for: self)
        if hasMouse { cursorUpdate(with: NSEvent()) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentCursor())
    }

    private func currentCursor() -> NSCursor {
        guard let c = controller else { return .arrow }
        let tool = c.tool
        if state.isZoomed {
            return Prefs.cursorMode == .toolSymbol ? CursorFactory.crosshair() : .crosshair
        }
        if Prefs.cursorMode == .toolSymbol {
            switch tool {
            case .pen, .eraser, .line, .arrow, .doubleArrow, .rect, .rectFilled,
                 .ellipse, .ellipseFilled, .check, .cross,
                 .number, .spotlight, .blur, .pixelate:
                return CursorFactory.dot(size: max(6, c.penSize))
            case .text:
                return CursorFactory.text()
            case .magnifier:
                return CursorFactory.magnifier()
            default:
                return CursorFactory.crosshair()
            }
        }
        switch tool {
        case .text: return .iBeam
        case .magnifier: return CursorFactory.magnifier()
        case .pen, .eraser: return .crosshair
        default: return .crosshair
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor().set()
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if state.isZoomed {
            drawZoom(ctx)
        } else {
            CanvasRenderer.drawBackground(state, in: ctx)
            if let layerImg = state.layer.snapshot() {
                CanvasRenderer.drawFullImage(ctx, layerImg, size: state.pointSize)
            }
            if let live = live, !live.isEraser { ShapeRenderer.draw(live, in: ctx) }
            drawRegion(ctx)
            drawHUD()
        }
    }

    private func drawZoom(_ ctx: CGContext) {
        let src = state.visibleSourceRect
        if let full = state.zoomSource() {
            let crop = CGRect(x: src.minX * state.scale, y: src.minY * state.scale,
                              width: src.width * state.scale, height: src.height * state.scale).integral
            ctx.saveGState()
            ctx.interpolationQuality = .none
            if let sub = full.cropping(to: crop) {
                CanvasRenderer.drawFullImage(ctx, sub, size: state.pointSize)
            } else {
                CanvasRenderer.drawFullImage(ctx, full, size: state.pointSize)
            }
            ctx.restoreGState()
        } else {
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(bounds)
        }

        // Ctrl 显示十字准线
        if state.showCrosshair || NSEvent.modifierFlags.contains(.control) {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 0.9).cgColor)
            ctx.setLineWidth(1)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: mousePoint.y)); ctx.addLine(to: CGPoint(x: bounds.width, y: mousePoint.y))
            ctx.move(to: CGPoint(x: mousePoint.x, y: 0)); ctx.addLine(to: CGPoint(x: mousePoint.x, y: bounds.height))
            ctx.strokePath()
            ctx.restoreGState()
        }
        drawHUD()
    }

    private func drawRegion(_ ctx: CGContext) {
        guard let r = state.region else { return }
        ctx.saveGState()
        ctx.setLineWidth(1)
        NSColor.white.setStroke()
        ctx.stroke(r)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        NSColor.black.setStroke()
        ctx.stroke(r)
        ctx.restoreGState()
        // 顶部拖动条
        NSColor(srgbRed: 0.1, green: 0.35, blue: 0.85, alpha: 0.85).setFill()
        NSBezierPath(rect: NSRect(x: r.minX, y: r.minY, width: r.width, height: 10)).fill()
        let label = "\(Int(r.width * state.scale)) × \(Int(r.height * state.scale)) px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (label as NSString).draw(at: NSPoint(x: r.minX + 3, y: r.minY - 1), withAttributes: attrs)
    }

    private func drawHUD() {
        guard let c = controller, hasMouse else { return }
        let px = Int(mousePoint.x * state.scale)
        let py = Int(mousePoint.y * state.scale)

        var parts: [String] = []
        if state.isZoomed {
            parts.append("\(Int(state.zoom))×")
            parts.append("X \(px)  Y \(py)")
            if let full = state.zoomSource(),
               let col = PixelSampler.color(of: full, at: CGPoint(x: mousePoint.x * state.scale, y: mousePoint.y * state.scale)) {
                parts.append(col.hexString)
            }
        } else {
            parts.append("X \(px)  Y \(py)")
            if c.tool == .region, let r = state.region {
                parts.append("\(Int(r.minX * state.scale)),\(Int(r.minY * state.scale))  \(Int(r.width * state.scale))×\(Int(r.height * state.scale))")
            }
        }
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: "   ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let s = text as NSString
        let size = s.size(withAttributes: attrs)
        var origin = NSPoint(x: mousePoint.x + 16, y: mousePoint.y + 18)
        if origin.x + size.width + 12 > bounds.width { origin.x = mousePoint.x - size.width - 16 }
        if origin.y + size.height + 8 > bounds.height { origin.y = mousePoint.y - size.height - 12 }
        let box = NSRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        s.draw(at: origin, withAttributes: attrs)
    }

    // MARK: 鼠标

    private func pt(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func constrained(_ a: CGPoint, _ b: CGPoint, square: Bool, snap45: Bool) -> CGPoint {
        var end = b
        if snap45 {
            let dx = b.x - a.x, dy = b.y - a.y
            let ang = atan2(dy, dx)
            let step = (ang / (.pi / 4)).rounded() * (.pi / 4)
            let len = sqrt(dx * dx + dy * dy)
            end = CGPoint(x: a.x + cos(step) * len, y: a.y + sin(step) * len)
        } else if square {
            let dx = b.x - a.x, dy = b.y - a.y
            let m = max(abs(dx), abs(dy))
            end = CGPoint(x: a.x + (dx < 0 ? -m : m), y: a.y + (dy < 0 ? -m : m))
        }
        return end
    }

    private func makeRect(_ a: CGPoint, _ b: CGPoint, constrain: Bool) -> CGRect {
        var e = b
        if constrain {
            let dx = b.x - a.x, dy = b.y - a.y
            let m = max(abs(dx), abs(dy))
            e = CGPoint(x: a.x + (dx < 0 ? -m : m), y: a.y + (dy < 0 ? -m : m))
        }
        return CGRect(x: min(a.x, e.x), y: min(a.y, e.y), width: abs(e.x - a.x), height: abs(e.y - a.y))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pt(event)
        mousePoint = p
        hasMouse = true
        controller?.canvasMouseMoved(canvas: state, localPoint: p, view: self, event: event)
        if state.isZoomed || controller?.tool == .region { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) {
        hasMouse = true
        controller?.setActive(state)
        currentCursor().set()
    }

    override func mouseExited(with event: NSEvent) {
        hasMouse = false
        controller?.magnifier?.orderOut(nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        window?.makeFirstResponder(self)
        dragRejected = false
        isDragging = false
        let p = pt(event)
        dragStart = p
        dragCurrent = p
        mousePoint = p
        hasMouse = true
        c.setActive(state)
        c.commitPendingEdit()

        if state.isZoomed {
            // 放大镜在缩放视图里同样可用（原版禁用的是"绘图"，放大镜是查看工具）
            if c.tool == .magnifier {
                c.magnifier?.toggleFactor()
                c.magnifier?.update(canvas: state, at: p, penSize: c.penSize)
                return
            }
            if event.modifierFlags.contains(.shift), let full = state.zoomSource(),
               let col = PixelSampler.color(of: full, at: CGPoint(x: p.x * state.scale, y: p.y * state.scale)) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(col.hexString, forType: .string)
                c.flashStatus(LS("Farbe \(col.hexString) kopiert", "Color \(col.hexString) copied", "已复制颜色 \(col.hexString)", "已複製顏色 \(col.hexString)"))
            }
            lastPan = p
            return
        }

        let strokeColor = c.currentColor
        let w = c.penSize

        switch c.tool {
        case .pen, .eraser:
            isDragging = true
            livePoints = [p]
            if c.tool == .eraser {
                // 橡皮擦直接作用于图层（.clear 混合），绝不能作为 live 画到视图上
                live = nil
                state.layer.apply(Stroke(shape: .freehand([p]), color: .black,
                                         width: c.penSize * 2.2, isEraser: true))
            } else {
                live = Stroke(shape: .freehand([p]), color: strokeColor, width: w)
            }
            needsDisplay = true
        case .line, .arrow, .doubleArrow, .rect, .rectFilled, .ellipse, .ellipseFilled,
             .spotlight, .blur, .pixelate:
            if (c.tool == .blur || c.tool == .pixelate) && state.currentBackgroundCG() == nil {
                c.flashStatus(LS("Dieses Blatt hat keinen Inhalt zum Unkenntlichmachen – nur bei „Aktueller Bildschirm“ oder „Aus Zwischenablage“ möglich.",
                                 "This sheet has nothing to redact — redaction works on “Current screen” or “Paste from clipboard”.",
                                 "当前画板没有可打码的内容 —— 打码只对「当前屏幕」和「从剪贴板粘贴」生效。",
                                 "當前畫板沒有可打碼的內容 —— 打碼只對「當前螢幕」和「從剪貼簿貼上」生效。"))
                dragRejected = true
                return
            }
            live = Stroke(shape: .line(p, p), color: strokeColor, width: w)
            isDragging = true
            needsDisplay = true
        case .number:
            commit(Stroke(shape: .number(state.nextNumber, p, w * 2.4 + 14),
                          color: strokeColor, width: w))
        case .text:
            beginTextEditing(at: p, color: strokeColor, width: w)
        case .check:
            commit(Stroke(shape: .check(p, w * 2.4 + 14), color: strokeColor, width: w))
        case .cross:
            commit(Stroke(shape: .cross(p, w * 2.4 + 14), color: strokeColor, width: w))
        case .region:
            if let r = state.region, r.insetBy(dx: -2, dy: -2).contains(p) {
                if p.y <= r.minY + 12 {
                    regionMoveOffset = CGPoint(x: p.x - r.minX, y: p.y - r.minY)
                } else {
                    regionMoveOffset = nil
                }
            } else {
                regionDragStart = p
                state.region = nil
                regionMoveOffset = nil
            }
            needsDisplay = true
        case .magnifier:
            c.magnifier?.toggleFactor()
            c.magnifier?.update(canvas: state, at: p, penSize: c.penSize)
        case .zoomIn:
            c.zoom(canvas: state, direction: 1, center: p)
        case .zoomOut:
            c.zoom(canvas: state, direction: -1, center: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let c = controller else { return }
        let p = pt(event)
        mousePoint = p
        dragCurrent = p
        if dragRejected { return }          // 本次拖动已被拒绝，别偷偷把笔画建起来

        if state.isZoomed {
            if c.tool == .magnifier {
                c.magnifier?.update(canvas: state, at: p, penSize: c.penSize)
                needsDisplay = true
                return
            }
            if let last = lastPan {
                state.zoomCenter.x -= (p.x - last.x) / state.zoom
                state.zoomCenter.y -= (p.y - last.y) / state.zoom
                clampZoomCenter()
            }
            lastPan = p
            needsDisplay = true
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        switch c.tool {
        case .pen, .eraser:
            livePoints.append(p)
            if c.tool == .eraser {
                let seg = Stroke(shape: .freehand([livePoints[livePoints.count - 2], p]),
                                 color: .black, width: c.penSize * 2.2, isEraser: true)
                state.layer.apply(seg)
            } else {
                live = Stroke(shape: .freehand(livePoints), color: c.currentColor, width: c.penSize)
            }
            needsDisplay = true
        case .line:
            live = Stroke(shape: .line(dragStart, constrained(dragStart, p, square: false, snap45: shift)),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .arrow:
            live = Stroke(shape: .arrow(dragStart, constrained(dragStart, p, square: false, snap45: shift)),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .doubleArrow:
            live = Stroke(shape: .doubleArrow(dragStart, constrained(dragStart, p, square: false, snap45: shift)),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .rect:
            live = Stroke(shape: .rect(makeRect(dragStart, p, constrain: shift)), color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .rectFilled:
            live = Stroke(shape: .rectFilled(makeRect(dragStart, p, constrain: shift)), color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .ellipse:
            live = Stroke(shape: .ellipse(makeRect(dragStart, p, constrain: shift)), color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .ellipseFilled:
            live = Stroke(shape: .ellipseFilled(makeRect(dragStart, p, constrain: shift)), color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .spotlight:
            live = Stroke(shape: .spotlight(makeRect(dragStart, p, constrain: shift)),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .blur:
            live = Stroke(shape: .redact(makeRect(dragStart, p, constrain: shift), .blur),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .pixelate:
            live = Stroke(shape: .redact(makeRect(dragStart, p, constrain: shift), .pixelate),
                          color: c.currentColor, width: c.penSize)
            needsDisplay = true
        case .region:
            if let off = regionMoveOffset, let r = state.region {
                state.region = CGRect(x: p.x - off.x, y: p.y - off.y, width: r.width, height: r.height)
            } else if regionDragStart != nil {
                state.region = makeRect(dragStart, p, constrain: shift)
            }
            needsDisplay = true
        case .magnifier:
            c.magnifier?.update(canvas: state, at: p, penSize: c.penSize)
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let c = controller else { return }
        isDragging = false
        if dragRejected { dragRejected = false; live = nil; needsDisplay = true; return }
        if state.isZoomed { lastPan = nil; return }

        switch c.tool {
        case .pen:
            if let s = live { commit(s) }
        case .eraser:
            let pts = livePoints
            live = nil
            if pts.count > 1 {
                state.strokes.append(Stroke(shape: .freehand(pts), color: .black,
                                            width: c.penSize * 2.2, isEraser: true))
                state.undoneStrokes.removeAll()
                c.didChangeStrokes(state)
            }
        case .line, .arrow, .doubleArrow, .rect, .rectFilled, .ellipse, .ellipseFilled:
            if let s = live { commit(s) }
        case .spotlight, .blur, .pixelate:
            // 拖得太小就当作误触，不留下一条没有意义的笔画
            if let s = live, case .spotlight(let r) = s.shape, r.width > 6, r.height > 6 {
                commit(s)
            } else if let s = live, case .redact(let r, _) = s.shape, r.width > 6, r.height > 6 {
                commit(s)
            } else {
                live = nil
                needsDisplay = true
            }
        case .region:
            regionDragStart = nil
            regionMoveOffset = nil
            if let r = state.region, r.width < 2 || r.height < 2 { state.region = nil }
            needsDisplay = true
        default:
            break
        }
        live = nil
        livePoints = []
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        let p = pt(event)
        c.showContextMenu(at: p, in: self, event: event)
    }

    private func commit(_ s: Stroke) {
        state.strokes.append(s)
        state.undoneStrokes.removeAll()      // 新操作让重做栈失效
        if case .spotlight = s.shape {
            // 新的聚焦要让旧的失效，必须整体重放（增量 apply 撤不掉旧的那一层压暗）
            state.rebuild()
        } else {
            state.layer.apply(s)
        }
        live = nil
        livePoints = []
        state.invalidateZoomCache()
        controller?.didChangeStrokes(state)
        needsDisplay = true
    }

    // MARK: 文本

    private func beginTextEditing(at p: CGPoint, color: NSColor, width: CGFloat) {
        commitPendingEdit()
        let fontSize = max(13, width * 1.15 + 10)
        let box = TextEditBox(origin: p, fontSize: fontSize, color: color)
        box.onCommit = { [weak self] text, origin, size in
            guard let self else { return }
            // 必须先清掉引用：否则下一次点击画布时 commitPendingEdit() 会重复提交同一段文字
            self.editBox = nil
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.commit(Stroke(shape: .text(text, origin, size), color: color, width: width))
        }
        box.onCancel = { [weak self] in
            self?.editBox = nil
            self?.needsDisplay = true
        }
        addSubview(box)
        editBox = box
        box.beginEditing()
        needsDisplay = true
    }

    func commitPendingEdit() {
        guard let box = editBox else { return }
        editBox = nil
        let text = box.tv.string
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fontSize = box.fontSize
            commit(Stroke(shape: .text(text, box.frame.origin, fontSize), color: box.tv.textColor ?? .red, width: fontSize))
        }
        box.removeFromSuperview()
    }

    private func clampZoomCenter() {
        let half = CGPoint(x: state.pointSize.width / (2 * state.zoom), y: state.pointSize.height / (2 * state.zoom))
        state.zoomCenter.x = min(max(half.x, state.zoomCenter.x), max(half.x, state.pointSize.width - half.x))
        state.zoomCenter.y = min(max(half.y, state.zoomCenter.y), max(half.y, state.pointSize.height - half.y))
    }

    // MARK: 缩放视图

    func enterZoom(_ level: CGFloat, center: CGPoint?) {
        if let c = center { state.zoomCenter = c }
        state.zoom = max(1, min(10, level))
        state.invalidateZoomCache()
        if state.zoom <= 1.0001 { state.zoom = 1 }
        clampZoomCenter()
        refreshCursor()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let c = controller, state.isZoomed, Prefs.wheelZoom else { return }
        let dy = event.scrollingDeltaY
        if abs(dy) < 0.1 { return }
        let p = pt(event)
        mousePoint = p
        guard applyWheelZoom(delta: dy > 0 ? 1 : -1, at: p) else { return }
        c.zoomToolSync(zoomed: state.zoom > 1)
        needsDisplay = true
    }

    /// 以光标位置为锚点缩放：缩放前后光标下的那个源像素必须保持不动。
    /// 返回是否真的改变了倍率。
    @discardableResult
    func applyWheelZoom(delta: CGFloat, at p: CGPoint) -> Bool {
        let old = state.zoom
        let next = delta > 0 ? min(10, old + 1) : max(1, old - 1)
        guard next != old else { return false }

        let src = state.visibleSourceRect
        let anchor = CGPoint(x: src.minX + p.x / old, y: src.minY + p.y / old)
        state.zoom = next
        // 令 anchor 在 1× 屏幕坐标 p 处保持不变：
        //   anchor = (center - size/(2·next)) + p/next   ⇒   center = anchor - (p - size/2)/next
        state.zoomCenter = CGPoint(x: anchor.x - (p.x - state.pointSize.width / 2) / next,
                                   y: anchor.y - (p.y - state.pointSize.height / 2) / next)
        clampZoomCenter()
        state.invalidateZoomCache()
        return true
    }

    /// 按住 Ctrl 显示十字准线，必须在不移动鼠标时也刷新
    override func flagsChanged(with event: NSEvent) {
        if state.isZoomed { needsDisplay = true }
        super.flagsChanged(with: event)
    }

    // MARK: 键盘

    override func keyDown(with event: NSEvent) {
        if controller?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 画布是文本编辑框的父视图，performKeyEquivalent 会先到这里。
        // 文本编辑期间必须把 ⌘C/⌘V/⌘Z 让给编辑框，否则没法复制/粘贴自己输入的文字。
        if let fr = window?.firstResponder, fr is NSTextView || fr is NSTextField {
            return super.performKeyEquivalent(with: event)
        }
        if controller?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// 取消进行中的拖动（ESC）。不结束会话，也不提交任何笔画。
    func cancelDrag() {
        guard isDragging else { return }
        isDragging = false
        dragRejected = true          // 让紧随其后的 mouseUp 不再提交
        live = nil
        livePoints = []
        needsDisplay = true
    }

    func moveRegionBy(dx: CGFloat, dy: CGFloat) {
        guard var r = state.region else { return }
        r.origin.x += dx
        r.origin.y += dy
        state.region = r
        needsDisplay = true
    }
}

// MARK: - 光标工厂

enum CursorFactory {
    private static var cache: [String: NSCursor] = [:]

    static func dot(size: CGFloat) -> NSCursor {
        let key = "dot\(Int(size))"
        if let c = cache[key] { return c }
        let d = max(8, size + 6)
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        NSColor.black.setStroke()
        let p = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: d - 3, height: d - 3))
        p.lineWidth = 1.5
        p.stroke()
        NSColor.white.setStroke()
        let p2 = NSBezierPath(ovalIn: NSRect(x: 0.75, y: 0.75, width: d - 1.5, height: d - 1.5))
        p2.lineWidth = 1
        p2.stroke()
        img.unlockFocus()
        let c = NSCursor(image: img, hotSpot: NSPoint(x: d / 2, y: d / 2))
        cache[key] = c
        return c
    }

    static func crosshair() -> NSCursor {
        if let c = cache["cross"] { return c }
        let d: CGFloat = 21
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        NSColor.white.setStroke()
        let w = NSBezierPath()
        w.move(to: NSPoint(x: d / 2, y: 1)); w.line(to: NSPoint(x: d / 2, y: d - 1))
        w.move(to: NSPoint(x: 1, y: d / 2)); w.line(to: NSPoint(x: d - 1, y: d / 2))
        w.lineWidth = 3
        w.stroke()
        NSColor.black.setStroke()
        let b = NSBezierPath()
        b.move(to: NSPoint(x: d / 2, y: 1)); b.line(to: NSPoint(x: d / 2, y: d - 1))
        b.move(to: NSPoint(x: 1, y: d / 2)); b.line(to: NSPoint(x: d - 1, y: d / 2))
        b.lineWidth = 1
        b.stroke()
        img.unlockFocus()
        let c = NSCursor(image: img, hotSpot: NSPoint(x: d / 2, y: d / 2))
        cache["cross"] = c
        return c
    }

    static func text() -> NSCursor {
        if let c = cache["text"] { return c }
        let img = NSImage(size: NSSize(width: 18, height: 22))
        img.lockFocus()
        let s = "I" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let sz = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: (18 - sz.width) / 2, y: 1), withAttributes: attrs)
        img.unlockFocus()
        let c = NSCursor(image: img, hotSpot: NSPoint(x: 9, y: 11))
        cache["text"] = c
        return c
    }

    static func magnifier() -> NSCursor {
        if let c = cache["mag"] { return c }
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        if let sym = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let c = NSCursor(image: sym, hotSpot: NSPoint(x: 6, y: 16))
            cache["mag"] = c
            return c
        }
        return .crosshair
    }
}
