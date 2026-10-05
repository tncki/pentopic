// CanvasView.swift — 每块屏幕的画布状态 + 绘制视图（全部绘图工具）
import AppKit

// MARK: - 画布状态（每块屏幕一份）

final class CanvasState {
    let screen: NSScreen
    /// 画布在屏幕坐标系里的位置与大小（点）。
    /// 整屏捕捉时等于 screen.frame；「区域捕捉」和「窗口捕捉」时是那一小块。
    let rect: CGRect
    let pointSize: CGSize
    let scale: CGFloat
    let frozenCG: CGImage?
    let frozenImage: NSImage?
    let layer: AnnotationLayer

    var strokes: [Stroke] = []
    /// 撤销 / 重做栈，存的是**整份笔画快照**。
    ///
    /// 早先的实现直接在 `strokes` 上 `removeLast()`，只能表示"追加"这一种操作。
    /// 而删除、对齐、移动、组合改的都是数组中间的元素 —— 撤销会弹掉另一条笔画，
    /// 删除因此完全不可撤销。快照能统一表示所有修改，也是唯一能覆盖编辑功能的做法。
    var undoStack: [[Stroke]] = []
    var redoStack: [[Stroke]] = []

    /// 快照数量上限。一份快照就是一组值类型，笔画多时也才几百 KB，
    /// 但没必要无限留。
    private static let undoLimit = 60

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 在任何会修改 strokes 的操作**之前**调用
    func beginEdit() { pushUndoSnapshot(strokes) }

    /// 推入一份**事先捕获**的快照。
    /// 拖动这类连续操作只在开始时捕获一次，否则每个鼠标移动都会记一条。
    func pushUndoSnapshot(_ snapshot: [Stroke]) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    @discardableResult
    func undoEdit() -> Bool {
        guard let prev = undoStack.popLast() else { return false }
        redoStack.append(strokes)
        strokes = prev
        pruneSelection()
        rebuild()
        return true
    }

    @discardableResult
    func redoEdit() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(strokes)
        strokes = next
        pruneSelection()
        rebuild()
        return true
    }
    var region: CGRect?
    /// 自由手绘选区（多边形，画布局部坐标）。非空时优先于 region。
    var regionPath: [CGPoint]?

    /// 选中的笔画 id（选择工具的产物）
    var selection: Set<UUID> = []

    var selectedStrokes: [Stroke] { strokes.filter { selection.contains($0.id) } }

    /// 选区总包围盒
    var selectionBounds: CGRect? {
        let sel = selectedStrokes
        guard let f = sel.first else { return nil }
        var r = f.shape.bounds
        for s in sel.dropFirst() { r = r.union(s.shape.bounds) }
        return r
    }

    /// 命中测试：返回最上面（最后画的）命中的笔画
    func stroke(at p: CGPoint, tolerance: CGFloat = 7) -> Stroke? {
        for s in strokes.reversed() where !s.isEraser {
            if s.shape.hitTest(p, tolerance: tolerance + s.width / 2) { return s }
        }
        return nil
    }

    /// 把一条笔画展开成"整组"。组合内的笔画在选择和移动时视为一体。
    func expandGroup(of stroke: Stroke) -> Set<UUID> {
        guard let g = stroke.groupID else { return [stroke.id] }
        return Set(strokes.filter { $0.groupID == g }.map { $0.id })
    }

    /// 丢掉已经不存在的笔画 id。
    /// 撤销 / 清空之后 selection 里会留下悬空引用 —— 计数会虚高，
    /// `selection.count` 也就不再等于"选中的笔画数"。
    func pruneSelection() {
        let alive = Set(strokes.map { $0.id })
        selection.formIntersection(alive)
    }

    /// 平移选中的笔画
    func moveSelection(dx: CGFloat, dy: CGFloat) {
        guard !selection.isEmpty, dx != 0 || dy != 0 else { return }
        strokes = strokes.map { selection.contains($0.id) ? $0.translated(dx: dx, dy: dy) : $0 }
        rebuild()
    }
    var background: BackgroundKind = .currentScreen
    var clipboardCG: CGImage?
    var clipboardSize: CGSize = .zero

    var zoom: CGFloat = 1
    var zoomCenter: CGPoint
    var showCrosshair = false
    var composedCache: CGImage?

    var isZoomed: Bool { zoom > 1.0001 }

    /// - Parameters:
    ///   - rect:  画布在屏幕坐标系里的位置与大小（点）。整屏捕捉传 screen.frame。
    ///   - image: 冻结的底图（像素尺寸应为 rect.size × scale）。nil 表示捕捉失败，退化成白板。
    init?(screen: NSScreen, image: CGImage?, rect: CGRect, scale: CGFloat) {
        self.screen = screen
        self.rect = rect
        self.pointSize = rect.size
        self.scale = scale
        self.frozenCG = image
        self.frozenImage = image.map { NSImage(cgImage: $0, size: rect.size) }

        let pw = Int((rect.width * scale).rounded())
        let ph = Int((rect.height * scale).rounded())
        guard let l = AnnotationLayer(pixelWidth: pw, pixelHeight: ph, scale: scale) else { return nil }
        self.layer = l
        self.zoomCenter = CGPoint(x: rect.width / 2, y: rect.height / 2)

        // 打码要读底图。用闭包而不是快照 —— 底图会随「空白纸 / 剪贴板」变化。
        l.backgroundProvider = { [weak self] in self?.currentBackgroundCG() }
        l.backgroundScale = scale
    }

    /// 整屏捕捉的便捷构造
    convenience init?(screen: NSScreen, captured: CapturedScreen?) {
        self.init(screen: screen,
                  image: captured?.cgImage,
                  rect: screen.frame,
                  scale: screen.backingScaleFactor)
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
    /// 合成画布。
    /// - Parameters:
    ///   - crop: 非空时按该矩形裁剪
    ///   - path: 非空时按多边形遮罩（自由手绘选区）
    /// 早先这里叫 `composeCG(region:)`，参数名遮蔽了同名属性，
    /// 而 `regionPath` 又无条件生效 —— 于是"取整张图"在有手绘选区时拿到的是裁过的图。
    func composeCG(crop: CGRect? = nil, path: [CGPoint]? = nil) -> CGImage? {
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

        // 自由手绘选区：按路径做遮罩，只保留多边形内部
        if let path, path.count >= 3 {
            let xs = path.map { $0.x }, ys = path.map { $0.y }
            let box = CGRect(x: xs.min()!, y: ys.min()!,
                             width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let px = CGRect(x: box.minX * scale, y: box.minY * scale,
                            width: box.width * scale, height: box.height * scale).integral
            let pw2 = Int(px.width), ph2 = Int(px.height)
            let cs2 = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard pw2 > 1, ph2 > 1,
                  let mctx = CGContext(data: nil, width: pw2, height: ph2, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: cs2,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return full }
            mctx.scaleBy(x: scale, y: scale)
            mctx.translateBy(x: -box.minX, y: box.maxY)
            mctx.scaleBy(x: 1, y: -1)
            let mp = CGMutablePath()
            mp.move(to: path[0])
            for p in path.dropFirst() { mp.addLine(to: p) }
            mp.closeSubpath()
            mctx.addPath(mp)
            mctx.clip()
            // clip 之后再画整张图，落进画布的只有多边形内部
            mctx.translateBy(x: box.minX, y: -box.maxY)
            mctx.scaleBy(x: 1, y: -1)
            mctx.translateBy(x: 0, y: pointSize.height)
            mctx.scaleBy(x: 1, y: -1)
            mctx.draw(full, in: CGRect(origin: .zero, size: pointSize))
            return mctx.makeImage() ?? full
        }

        guard let r = crop else { return full }
        let crop = CGRect(x: r.minX * scale, y: r.minY * scale,
                          width: r.width * scale, height: r.height * scale).integral
        return full.cropping(to: crop) ?? full
    }

    /// 缩放视图里显示的源图（背景 + 标注），带缓存
    func zoomSource() -> CGImage? {
        if let c = composedCache { return c }
        let c = composeCG()
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
    /// 把整张图旋转 90°。`clockwise` 为真表示顺时针。
    /// 图像坐标系 y 向下、CG 上下文 y 向上，所以"顺时针"在这里是 -90°。
    static func rotate90(_ img: CGImage, clockwise: Bool) -> CGImage? {
        let w = img.width, h = img.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(h) / 2, y: CGFloat(w) / 2)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

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

    /// 本次按下是否由 ⇧ 触发了临时指针（鼠标松开时要还原）
    private var shiftMoveActive = false
    private var marquee: CGRect?            // 框选矩形
    private var marqueeStart: CGPoint?
    private var selectDragLast: CGPoint?
    /// 拖动开始前的笔画快照。整次拖动只记一条撤销，而不是每个鼠标移动记一条。
    private var dragUndoSnapshot: [Stroke]?
    private var dragDidMove = false
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

    /// 上一次画出的面板位置，用于只重画这一小块
    private var lastLoupeDrawn: CGRect = .zero

    private func currentCursor() -> NSCursor {
        guard let c = controller else { return .arrow }
        let tool = c.tool

        // 拖动过程中光标保持不变。否则拖动时指针划过笔画/空白会来回跳，很廉价。
        if isDragging {
            switch tool {
            case .select, .region: return .closedHand
            case .text: return .iBeam
            default: return .crosshair
            }
        }

        // 指针与选区工具：光标要反映"按下去会发生什么"，而不是固定一个箭头。
        // ⌥ 会把"移动"变成"框选"，光标也跟着变回十字。
        let marquee = NSEvent.modifierFlags.contains(.option)
        if !state.isZoomed, tool == .select || tool == .region {
            let overRegion = state.region?.insetBy(dx: -3, dy: -3).contains(mousePoint) == true
            let overStroke = hasMouse && state.stroke(at: mousePoint) != nil
            if !marquee, overStroke || overRegion {
                return .openHand                       // 下面有抓得住的东西 → 张开的手
            }
            // 指针工具：空白处按下 = 框选已有笔画 → 箭头
            // 选区工具：空白处按下 = 画一个新选区 → 十字（正在"画"东西，不是"选"）
            return tool == .region ? .crosshair : .arrow
        }

        // 缩放视图里只查看，不给工具专属光标（除了取色与放大镜，它们仍是"取用"性质）
        if state.isZoomed {
            switch tool {
            case .eyedropper: return CursorFactory.eyedropper()
            case .magnifier: return CursorFactory.magnifier()
            default: return Prefs.cursorMode == .toolSymbol ? CursorFactory.crosshair() : .crosshair
            }
        }
        if Prefs.cursorMode == .toolSymbol {
            switch tool {
            case .pen, .eraser, .line, .arrow, .doubleArrow, .rect, .rectFilled,
                 .ellipse, .ellipseFilled, .check, .cross,
                 .number, .spotlight, .blur, .pixelate, .ruler:
                return CursorFactory.dot(size: max(6, c.penSize))
            case .text:
                return CursorFactory.text()
            case .magnifier:
                return CursorFactory.magnifier()
            case .eyedropper:
                return CursorFactory.eyedropper()
            case .select:
                return .arrow
            default:
                return CursorFactory.crosshair()
            }
        }
        switch tool {
        case .text: return .iBeam
        case .magnifier: return CursorFactory.magnifier()
        case .eyedropper: return CursorFactory.eyedropper()
        default: return .crosshair          // 画笔、橡皮、图形、选区、标尺…都是十字
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor().set()
    }

    // ---- 自检用 -----------------------------------------------------------------
    /// 按当前状态算出光标。光标是否"符合逻辑"只能靠断言锁住 ——
    /// 眼睛看一遍很容易，但下次改工具时就忘了同步。
    var cursorForTest: NSCursor { currentCursor() }
    /// 自检里模拟"鼠标悬停在某处"，而不必真的合成一个 mouseMoved 事件。
    func setHoverForTest(_ p: CGPoint) { mousePoint = p; hasMouse = true }

    /// 复制光标所在像素的色值（取色放大面板上写的就是这个快捷键）。
    @discardableResult
    func copyColourUnderCursor(canvas st: CanvasState) -> String? {
        guard hasMouse, let full = st.zoomSource(),
              let col = PixelSampler.color(of: full, at: CGPoint(x: mousePoint.x * st.scale,
                                                                 y: mousePoint.y * st.scale))
        else { return nil }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(col.hexString, forType: .string)
        return col.hexString
    }
    func clearHoverForTest() { hasMouse = false }

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
            drawSelection(ctx)
            drawRegion(ctx)
            drawHUD()
            drawEyedropperLoupe(ctx)
        }
    }

    /// 取色器悬停时的放大镜。
    ///
    /// 取色的难点从来不是"点得准"，而是**看不清自己点的是哪个像素** ——
    /// 屏幕上相邻两个像素常常只差一点点颜色。所以光标旁边直接给出放大后的
    /// 画面与十字准线，不用先点一下再看结果。
    /// 放大面板的几何。**绘制与脏矩形必须用同一套算法** ——
    /// 两边各算一次的话，位置一旦对不上就会在屏幕上留下残影。
    static let loupeWidth: CGFloat = 204
    static let loupeMagHeight: CGFloat = 152
    static let loupeRowHeight: CGFloat = 24
    static var loupeHeight: CGFloat { loupeMagHeight + 1 + loupeRowHeight * 3 + 14 }

    func loupeRect(for p: CGPoint) -> CGRect {
        let w = Self.loupeWidth, h = Self.loupeHeight
        var ox = p.x + 22, oy = p.y + 22
        if ox + w > bounds.maxX - 6 { ox = p.x - 22 - w }
        if oy + h > bounds.maxY - 6 { oy = p.y - 22 - h }
        return CGRect(x: max(6, ox), y: max(6, oy), width: w, height: h)
    }

    /// 取色/查看用的放大面板。根据设置常驻，不再只服务于取色器 ——
    /// "看不清自己点的是哪个像素"这个问题，在你还没切到取色器时就已经存在了。
    private func drawEyedropperLoupe(_ ctx: CGContext) {
        guard Prefs.loupeEnabled, hasMouse, !state.isZoomed,
              controller?.tool != .magnifier else { return }   // 放大镜工具有自己的浮窗
        guard let full = state.zoomSource() else { return }   // 带缓存，悬停时不会每帧重合成

        let w = Self.loupeWidth
        let magH = Self.loupeMagHeight
        let rowH = Self.loupeRowHeight
        let padX: CGFloat = 18
        let infoH = rowH * 3 + 14
        let radius: CGFloat = 15
        let h = Self.loupeHeight

        let px = min(max(Int(mousePoint.x * state.scale), 0), full.width - 1)
        let py = min(max(Int(mousePoint.y * state.scale), 0), full.height - 1)
        guard let col = PixelSampler.color(of: full, at: CGPoint(x: px, y: py)) else { return }

        let panel = loupeRect(for: mousePoint)
        let magRect = CGRect(x: panel.minX, y: panel.minY, width: w, height: magH)
        lastLoupeDrawn = panel

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // ---- 面板：浅色、圆角、细边框 ----
        let outline = CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 14,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
        ctx.setFillColor(NSColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 0.97).cgColor)
        ctx.addPath(outline); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // ---- 放大区：裁到面板圆角内再画 ----
        ctx.saveGState()
        ctx.addPath(outline); ctx.clip()
        // 显示约 34×25 个屏幕像素；关掉插值 → 像素边界清楚，看得见自己取的是哪一格
        let zoom: CGFloat = 6
        let sw = max(3, (w / zoom).rounded()), sh = max(3, (magH / zoom).rounded())
        let src = CGRect(x: CGFloat(px) - sw / 2, y: CGFloat(py) - sh / 2, width: sw, height: sh)
        // 源矩形要**夹回图像范围内**。cropping(to:) 要求矩形完全落在图内，
        // 光标贴边时它返回 nil —— 早先直接填了一片白色，看起来像"放大区是空的"。
        // 夹取之后按同样的比例缩小绘制区域，边缘处也始终有真实内容。
        let inside = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        let clipped = src.intersection(inside)
        if !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
           let sub = full.cropping(to: clipped) {
            let kx = magRect.width / src.width, ky = magRect.height / src.height
            let dst = CGRect(x: magRect.minX + (clipped.minX - src.minX) * kx,
                             y: magRect.minY + (clipped.minY - src.minY) * ky,
                             width: clipped.width * kx, height: clipped.height * ky)
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.translateBy(x: dst.minX, y: dst.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(sub, in: CGRect(origin: .zero, size: dst.size))
            ctx.restoreGState()
        } else {
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(magRect)
        }
        // 取景框：内容本身是纯色时，没有这圈线就分不清"放大区"和面板留白
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.20).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(magRect.insetBy(dx: 0.5, dy: 0.5))
        // 十字准线：先描一圈白，再画深绿 —— 深色和浅色画面上都看得见
        let cx = magRect.midX, cy = magRect.midY
        let bar: CGFloat = 9
        func cross(_ inset: CGFloat, _ color: NSColor, _ width: CGFloat) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.setLineCap(.butt)
            ctx.move(to: CGPoint(x: cx, y: magRect.minY + inset))
            ctx.addLine(to: CGPoint(x: cx, y: magRect.maxY - inset))
            ctx.move(to: CGPoint(x: magRect.minX + inset, y: cy))
            ctx.addLine(to: CGPoint(x: magRect.maxX - inset, y: cy))
            ctx.strokePath()
        }
        cross(0, .white, bar + 4)
        cross(0, NSColor(srgbRed: 0.16, green: 0.35, blue: 0.24, alpha: 1), bar)
        ctx.restoreGState()

        // ---- 分隔线 ----
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.13).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: panel.minX, y: magRect.maxY + 0.5))
        ctx.addLine(to: CGPoint(x: panel.maxX, y: magRect.maxY + 0.5))
        ctx.strokePath()

        // ---- 信息区：带标签的三行 ----
        let labelX = panel.minX + padX
        let valueX = panel.minX + padX + 74
        var rowY = magRect.maxY + 8
        func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                  _ color: NSColor, _ bold: Bool, _ mono: Bool) {
            let font: NSFont = mono
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
                : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            (str as NSString).draw(at: NSPoint(x: x, y: y),
                                   withAttributes: [.font: font, .foregroundColor: color])
        }
        let labelColor = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.44, alpha: 1)
        let valueColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)

        text(LS("Position", "Position", "坐标", "座標"), labelX, rowY, 13, labelColor, false, false)
        text("\(px), \(py)", valueX, rowY, 14, valueColor, true, true)
        rowY += rowH
        text(LS("Farbe", "Colour", "色值", "色值"), labelX, rowY, 13, labelColor, false, false)
        text(col.hexString, valueX, rowY, 14, valueColor, true, true)
        rowY += rowH
        text(LS("⌘+C kopiert den Farbwert", "⌘+C copies the colour",
                "按 ⌘+C 复制色值", "按 ⌘+C 複製色值"),
             labelX, rowY, 11.5,
             NSColor(srgbRed: 0.60, green: 0.60, blue: 0.62, alpha: 1), false, false)
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

    /// 选中笔画的虚线框 + 整体包围盒
    private func drawSelection(_ ctx: CGContext) {
        // 选择是**指针工具的编辑状态**：切到别的工具后不该继续显示虚线框。
        // 选择本身就留着 —— 切回指针还能继续用，省得重新框一遍。
        guard controller?.tool == .select else { return }
        let sel = state.selectedStrokes
        guard !sel.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineWidth(1)
        for s in sel {
            let r = s.shape.bounds.insetBy(dx: -3, dy: -3)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.stroke(r)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.stroke(r)
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // 多选时再画一个整体框
        if sel.count > 1, let all = state.selectionBounds {
            let r = all.insetBy(dx: -6, dy: -6)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [7, 5])
            ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor)
            ctx.stroke(r)
            ctx.setLineDash(phase: 0, lengths: [])
            // 角点提示可以拖动
            for c in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7))
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.strokeEllipse(in: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7))
            }
        }
        ctx.restoreGState()
        if let m = marquee {
            ctx.saveGState()
            ctx.setLineWidth(1)
            NSColor.white.setStroke(); ctx.stroke(m)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            NSColor.controlAccentColor.setStroke(); ctx.stroke(m)
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
            ctx.fill(m)
            ctx.restoreGState()
        }
    }

    private func drawRegion(_ ctx: CGContext) {
        // 自由手绘选区：描出多边形轮廓
        if let path = state.regionPath, path.count >= 2 {
            ctx.saveGState()
            let p = CGMutablePath()
            p.move(to: path[0])
            for q in path.dropFirst() { p.addLine(to: q) }
            p.closeSubpath()
            ctx.setLineWidth(1)
            NSColor.white.setStroke()
            ctx.addPath(p); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            NSColor.black.setStroke()
            ctx.addPath(p); ctx.strokePath()
            ctx.restoreGState()
            let xs = path.map { $0.x }, ys = path.map { $0.y }
            let label = "\(Int((xs.max()! - xs.min()!) * state.scale)) × \(Int((ys.max()! - ys.min()!) * state.scale)) px"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            (label as NSString).draw(at: NSPoint(x: xs.min()!, y: ys.min()! - 12), withAttributes: attrs)
            return
        }
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
            if c.tool == .region, let path = state.regionPath, path.count >= 2 {
                let xs = path.map { $0.x }, ys = path.map { $0.y }
                parts.append("\(Int((xs.max()! - xs.min()!) * state.scale))×\(Int((ys.max()! - ys.min()!) * state.scale))")
            } else if c.tool == .region, let r = state.region {
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
        // 光标要随鼠标**移动**实时变化，不能只在进入视图时设一次 ——
        // 指针工具划过笔画/选区/空白时，光标得跟着变。
        currentCursor().set()
        // 放大面板跟着鼠标走。**只重画面板所在的那两小块** ——
        // 常驻状态下每次鼠标移动都重绘整张 3K 画布太浪费。
        if Prefs.loupeEnabled, !state.isZoomed {
            let now = loupeRect(for: p).insetBy(dx: -3, dy: -3)
            setNeedsDisplay(now.union(lastLoupeDrawn))
        }
        // 选区工具要跟着画尺寸提示
        if state.isZoomed || controller?.tool == .region { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) {
        hasMouse = true
        controller?.setActive(state)
        currentCursor().set()
    }

    override func mouseExited(with event: NSEvent) {
        hasMouse = false
        if lastLoupeDrawn != .zero { setNeedsDisplay(lastLoupeDrawn.insetBy(dx: -3, dy: -3)); lastLoupeDrawn = .zero }
        controller?.magnifier?.orderOut(nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        window?.makeFirstResponder(self)
        dragRejected = false
        isDragging = false
        let p = pt(event)

        // ⇧ + 在已有笔画上按下 = 临时借用指针来移动它（松开鼠标还原当前工具）。
        // 按下点为空时不拦截 —— 形状工具的 ⇧ 仍然是"约束为正方形/正圆"。
        if event.modifierFlags.contains(.shift), c.tool != .select, !state.strokes.isEmpty,
           state.stroke(at: p) != nil {
            shiftMoveActive = true
            c.pushTemporaryTool(.select)
        }
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
            if c.tool == .eyedropper {
                c.sampleColor(canvas: state, at: p)
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
             .spotlight, .blur, .pixelate, .ruler:
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
            commit(Stroke(shape: .number(state.nextNumber, p, w * 2.4 + 14, Prefs.numberShape),
                          color: strokeColor, width: w))
        case .select:
            let shift = event.modifierFlags.contains(.shift)
            // ⌥：强制框选。选区内部默认是"拖动整个选区"，需要在这里面框选笔画时用它。
            let alt = event.modifierFlags.contains(.option)
            if let hit = state.stroke(at: p) {
                let ids = state.expandGroup(of: hit)
                if shift {
                    if state.selection.isSuperset(of: ids) { state.selection.subtract(ids) }
                    else { state.selection.formUnion(ids) }
                } else if !state.selection.contains(hit.id) {
                    state.selection = ids
                }
                // 点在已选中的笔画上 → 开始整体拖动
                if state.selection.contains(hit.id) { selectDragLast = p }
            } else if !alt, let r = state.region, r.insetBy(dx: -3, dy: -3).contains(p) {
                // 指针工具在选区内按下 —— 拖动整个选区。
                // 这是用户明确期待的行为："选择与移动"能移动选区。
                // 想在选区内部框选笔画时按住 ⌥：否则"在选区里拖动"就只有一个含义。
                if !shift { state.selection.removeAll() }
                regionMoveOffset = CGPoint(x: p.x - r.minX, y: p.y - r.minY)
            } else {
                if !shift { state.selection.removeAll() }
                marqueeStart = p
                marquee = CGRect(origin: p, size: .zero)
            }
            isDragging = true
            needsDisplay = true
        case .text:
            beginTextEditing(at: p, color: strokeColor, width: w)
        case .check:
            commit(Stroke(shape: .check(p, w * 2.4 + 14), color: strokeColor, width: w))
        case .cross:
            commit(Stroke(shape: .cross(p, w * 2.4 + 14), color: strokeColor, width: w))
        case .region:
            if Prefs.freeRegion {
                state.regionPath = [p]
                state.region = nil
                regionDragStart = p
                needsDisplay = true
                return
            }
            if let r = state.region, r.insetBy(dx: -3, dy: -3).contains(p) {
                // 整个选区都能拖。早先只允许抓顶部 12pt 的蓝条，中间是**死区** ——
                // 点了没反应，看起来就像"选区动不了"。
                regionMoveOffset = CGPoint(x: p.x - r.minX, y: p.y - r.minY)
            } else {
                regionDragStart = p
                state.region = nil
                regionMoveOffset = nil
            }
            needsDisplay = true
        case .eyedropper:
            c.sampleColor(canvas: state, at: p)
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
        case .select:
            // 拖动选区（指针工具在选区内按下时）
            if let off = regionMoveOffset, let r = state.region {
                state.region = CGRect(x: p.x - off.x, y: p.y - off.y, width: r.width, height: r.height)
                needsDisplay = true
                return
            }
            if let last = selectDragLast {
                if dragUndoSnapshot == nil { dragUndoSnapshot = state.strokes }
                state.moveSelection(dx: p.x - last.x, dy: p.y - last.y)
                selectDragLast = p
                dragDidMove = true
            } else if let start = marqueeStart {
                marquee = makeRect(start, p, constrain: false)
            }
            needsDisplay = true
            return
        case .ruler:
            let end = constrained(dragStart, p, square: false, snap45: shift)
            let px = hypot(end.x - dragStart.x, end.y - dragStart.y) * state.scale
            live = Stroke(shape: .ruler(dragStart, end, px), color: c.currentColor, width: c.penSize)
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
                if Prefs.freeRegion {
                    // 自由手绘：累积轨迹
                    var pts = state.regionPath ?? []
                    if let last = pts.last, hypot(p.x - last.x, p.y - last.y) > 2 { pts.append(p) }
                    else if pts.isEmpty { pts.append(p) }
                    state.regionPath = pts
                    state.region = nil
                } else if let fixed = Prefs.fixedRegionSize {
                    // 固定尺寸：左上角跟随光标，尺寸恒定
                    state.region = CGRect(x: min(dragStart.x, p.x), y: min(dragStart.y, p.y),
                                          width: fixed.width, height: fixed.height)
                    state.regionPath = nil
                } else {
                    state.region = makeRect(dragStart, p, constrain: shift)
                    state.regionPath = nil
                }
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
        defer {
            if shiftMoveActive {
                shiftMoveActive = false
                c.popTemporaryTool()
            }
        }
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
                state.beginEdit()
                state.strokes.append(Stroke(shape: .freehand(pts), color: .black,
                                            width: c.penSize * 2.2, isEraser: true))
                c.didChangeStrokes(state)
            }
        case .line, .arrow, .doubleArrow, .rect, .rectFilled, .ellipse, .ellipseFilled:
            if let s = live { commit(s) }
        case .select:
            let shift = event.modifierFlags.contains(.shift)
            if let m = marquee {
                let hits = state.strokes.filter { !$0.isEraser && $0.shape.bounds.intersects(m) }
                var ids = Set<UUID>()
                for h in hits { ids.formUnion(state.expandGroup(of: h)) }
                if shift { state.selection.formUnion(ids) } else { state.selection = ids }
            }
            // 整次拖动结束后再入栈；没真正移动过就不记，避免留下空操作
            if dragDidMove, let snap = dragUndoSnapshot { state.pushUndoSnapshot(snap) }
            dragUndoSnapshot = nil
            dragDidMove = false
            regionMoveOffset = nil          // 指针工具也可能在拖选区，别留残留状态
            marquee = nil; marqueeStart = nil; selectDragLast = nil
            c.syncModel()
            needsDisplay = true
        case .spotlight, .blur, .pixelate, .ruler:
            // 拖得太小就当作误触，不留下一条没有意义的笔画
            if let s = live, case .spotlight(let r) = s.shape, r.width > 6, r.height > 6 {
                commit(s)
            } else if let s = live, case .redact(let r, _) = s.shape, r.width > 6, r.height > 6 {
                commit(s)
            } else if let s = live, case .ruler(let a, let b, _) = s.shape,
                      hypot(b.x - a.x, b.y - a.y) > 8 {
                commit(s)
            } else {
                live = nil
                needsDisplay = true
            }
        case .region:
            regionDragStart = nil
            regionMoveOffset = nil
            if let path = state.regionPath, path.count < 3 { state.regionPath = nil }
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
        state.beginEdit()                    // 先存快照，再改
        state.strokes.append(s)
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

    override func keyUp(with event: NSEvent) {
        // 空格松开 → 还原借用的指针。没有这一步，空格会变成"按一下永久换工具"。
        if event.keyCode == 49 {
            controller?.popTemporaryTool()
            return
        }
        super.keyUp(with: event)
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

    static func eyedropper() -> NSCursor {
        if let c = cache["eyedrop"] { return c }
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        if let sym = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let c = NSCursor(image: sym, hotSpot: NSPoint(x: 2, y: 18))
            cache["eyedrop"] = c
            return c
        }
        return .crosshair
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
