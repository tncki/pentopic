// Windows.swift — 覆盖窗口 / 工具栏面板 / 放大镜 / 会话控制器
import AppKit
import SwiftUI

// MARK: - 冻结覆盖窗口

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 工具栏面板（不抢键盘焦点）

final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 放大镜

final class MagnifierView: NSView {
    var image: CGImage?
    var sourcePoint: CGPoint = .zero
    var scale: CGFloat = 1
    var factor: CGFloat = 2
    var viewSize: CGFloat = 140

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        guard let img = image else { return }
        let srcW = bounds.width / factor, srcH = bounds.height / factor
        let crop = CGRect(x: (sourcePoint.x - srcW / 2) * scale,
                          y: (sourcePoint.y - srcH / 2) * scale,
                          width: srcW * scale, height: srcH * scale).integral
        ctx.interpolationQuality = .none
        if let sub = img.cropping(to: crop) {
            CanvasRenderer.drawFullImage(ctx, sub, size: bounds.size)
        }
        // 边框 + 中心十字
        NSColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        NSColor(srgbRed: 1, green: 0.15, blue: 0.15, alpha: 0.85).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: bounds.midX - 8, y: bounds.midY)); cross.line(to: NSPoint(x: bounds.midX + 8, y: bounds.midY))
        cross.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 8)); cross.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 8))
        cross.lineWidth = 1
        cross.stroke()
    }
}

final class MagnifierPanel: NSPanel {
    private let mv = MagnifierView()
    private(set) var factor: CGFloat = 2
    private var side: CGFloat = 140
    private weak var lastCanvas: CanvasState?
    private var lastPoint: CGPoint = .zero
    private var lastPenSize: CGFloat = 5

    /// 原版：放大镜尺寸跟随"笔粗"设置。这里给足区分度（120 → 294 px）
    static func size(forPenSize p: CGFloat) -> CGFloat { max(120, min(360, 96 + p * 9)) }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 140, height: 140),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = mv
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func toggleFactor() {
        factor = factor >= 4 ? 2 : 4
        mv.factor = factor
        mv.needsDisplay = true
    }

    /// 笔粗变化时不需要移动鼠标也能立刻看到放大镜变大变小
    func applyPenSize(_ penSize: CGFloat) {
        lastPenSize = penSize
        let want = MagnifierPanel.size(forPenSize: penSize)
        if abs(want - side) > 0.5 {
            side = want
            setContentSize(NSSize(width: side, height: side))
            mv.viewSize = side
            mv.frame = NSRect(x: 0, y: 0, width: side, height: side)
            mv.needsDisplay = true
        }
        guard isVisible, let c = lastCanvas else { return }
        update(canvas: c, at: lastPoint, penSize: penSize)
    }

    func update(canvas: CanvasState, at point: CGPoint, penSize: CGFloat) {
        lastCanvas = canvas
        lastPoint = point
        lastPenSize = penSize
        let want = MagnifierPanel.size(forPenSize: penSize)
        if abs(want - side) > 0.5 {
            side = want
            setContentSize(NSSize(width: side, height: side))
            mv.viewSize = side
            mv.frame = NSRect(x: 0, y: 0, width: side, height: side)
        }
        mv.image = canvas.zoomSource()
        mv.scale = canvas.scale
        mv.sourcePoint = point
        mv.factor = factor
        mv.needsDisplay = true

        // 跟随鼠标，避开屏幕边缘
        let globalMouse = NSEvent.mouseLocation
        let screen = canvas.screen
        var x = globalMouse.x + 24
        var y = globalMouse.y - side - 24
        if x + side > screen.frame.maxX { x = globalMouse.x - side - 24 }
        if y < screen.frame.minY { y = globalMouse.y + 24 }
        setFrameOrigin(NSPoint(x: x, y: y))
        if !isVisible { orderFrontRegardless() }
    }
}

// MARK: - 短暂状态提示

final class ToastPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 0.86).cgColor
        box.layer?.cornerRadius = 10
        label.frame = NSRect(x: 10, y: 10, width: 240, height: 20)
        label.autoresizingMask = [.width, .height]
        box.addSubview(label)
        contentView = box
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ text: String) {
        label.stringValue = text
        let size = (text as NSString).size(withAttributes: [.font: label.font as Any])
        let w = min(560, size.width + 40)
        setContentSize(NSSize(width: w, height: 40))
        contentView?.frame = NSRect(x: 0, y: 0, width: w, height: 40)
        label.frame = NSRect(x: 10, y: 10, width: w - 20, height: 20)
        let m = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: m.x + 18, y: m.y + 22))
        orderFrontRegardless()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideNow), object: nil)
        perform(#selector(hideNow), with: nil, afterDelay: 1.4)
    }
    @objc private func hideNow() { orderOut(nil) }
}

// MARK: - 工具栏数据模型

final class ToolbarModel: ObservableObject {
    @Published var isActive = false
    @Published var tool: ToolKind = .pen
    @Published var swatchIndex: Int = 0
    @Published var penSizeIndex: Int = 1
    @Published var swatches: [Swatch] = Palette.standard
    @Published var zoomFactor: CGFloat = 1
    @Published var canUndo = false
    @Published var hasStrokes = false
    @Published var hasRegion = false
    @Published var screenName = ""
}

// MARK: - 会话控制器

final class SessionController: NSObject, NSMenuDelegate {

    static let shared = SessionController()

    let model = ToolbarModel()
    private(set) var isActive = false
    private(set) var canvases: [CanvasState] = []
    private var windows: [OverlayWindow] = []
    private var views: [CanvasView] = []
    private var toolbarPanel: ToolbarPanel?
    private var hostingView: NSHostingView<ToolbarView>?
    var magnifier: MagnifierPanel?
    private var toast: ToastPanel?
    private var startPanel: StartButtonPanel?
    private var previousApp: NSRunningApplication?

    private(set) var tool: ToolKind = .pen
    private(set) var swatchIndex: Int = 0
    private(set) var penSizeIndex: Int = 1
    var previousTool: ToolKind = .pen
    private(set) var activeIndex: Int = 0

    var activeCanvas: CanvasState? {
        guard canvases.indices.contains(activeIndex) else { return canvases.first }
        return canvases[activeIndex]
    }

    var penSize: CGFloat { PenSize.values[penSizeIndex] }
    var currentColor: NSColor { Palette.all[min(swatchIndex, Palette.all.count - 1)].color }

    // MARK: 生命周期

    func installStartPanel(_ p: StartButtonPanel) { startPanel = p }

    func start(synchronously: Bool = false) {
        guard !isActive else { return }
        // ensure() 在已授权时立即返回 true；否则循环引导授权，拿到权限后继续启动
        guard ScreenPermission.ensure() else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        isActive = true
        model.isActive = true

        startPanel?.orderOut(nil)
        Prefs.ensureFolders()

        let screens = NSScreen.screens
        if synchronously {
            captureAndBuild(screens: screens)
        } else {
            // 稍等一拍让启动按钮消失，再冻结屏幕
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                // 这 80ms 内用户可能已经按了 F9 取消，必须重新确认状态
                guard let self, self.isActive else { return }
                self.captureAndBuild(screens: screens)
            }
        }
    }

    private func captureAndBuild(screens: [NSScreen]) {
        guard isActive else { return }
        var caps: [CGDirectDisplayID: CapturedScreen] = [:]
        for s in screens {
            if let c = ScreenCapture.capture(screen: s) { caps[ScreenCapture.displayID(of: s)] = c }
        }
        buildSession(screens: screens, captured: caps)
    }

    private func buildSession(screens: [NSScreen], captured: [CGDirectDisplayID: CapturedScreen]) {
        teardownWindows()
        canvases.removeAll()
        var target: CanvasState?

        for screen in screens {
            let cap = captured[ScreenCapture.displayID(of: screen)]
            guard let st = CanvasState(screen: screen, captured: cap) else { continue }
            let view = CanvasView(state: st, controller: self)

            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.acceptsMouseMovedEvents = true
            w.isReleasedWhenClosed = false
            w.contentView = view
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()

            windows.append(w)
            views.append(view)
            canvases.append(st)
            if target == nil { target = st }
        }

        guard !canvases.isEmpty else { finish(quiet: true); return }

        // 安全网：权限显示已授予，但 ScreenCaptureKit 一张图都没拿到
        // （刚勾选权限、TCC 尚未对本进程生效时会发生）→ 明确告知需要重启
        if !ScreenCapture.fakeCapture && canvases.allSatisfy({ $0.frozenCG == nil }) {
            finish(quiet: true)
            Alert.error(LS("Bildschirm konnte nicht aufgenommen werden",
                           "Could not capture the screen",
                           "无法抓取屏幕画面", "無法抓取螢幕畫面"),
                        LS("Die Berechtigung ist gesetzt, aber macOS hat noch kein Bild geliefert. Bitte Pointofix einmal beenden und neu starten.",
                           "Permission is granted but macOS returned no image yet. Please quit and relaunch Pointofix.",
                           "权限已开启，但系统尚未返回画面。请退出 Pointofix 后重新启动一次。", "權限已開啟，但系統尚未返回畫面。請結束 Pointofix 後重新啟動一次。"))
            return
        }

        // 会话进行中注销全局热键：否则它会**系统级吞掉**该按键。
        // 例如把 ⌘P 设为热键后，注册状态下应用内的「打印」就再也收不到 ⌘P 了。
        // 会话中的按键改由 handleKeyEquivalent / handleKeyDown 匹配处理。
        GlobalHotKey.shared.unregister()

        // 选择默认画布
        if let first = canvases.first {
            switch Prefs.screenMode {
            case .first: activeIndex = 0
            case .second: activeIndex = min(1, canvases.count - 1)
            case .mouse:
                let m = NSEvent.mouseLocation
                activeIndex = canvases.firstIndex(where: { $0.screen.frame.contains(m) }) ?? 0
            }
            _ = first
        }

        let keyWindow = windows.indices.contains(activeIndex) ? windows[activeIndex] : windows[0]
        keyWindow.makeKeyAndOrderFront(nil)
        if let v = views.first(where: { $0.state === activeCanvas }) { keyWindow.makeFirstResponder(v) }

        showToolbar()
        magnifier = MagnifierPanel()
        toast = ToastPanel()
        SettingsWindowController.shared.adaptToSession()
        syncModel()
        applyTool(tool, silent: true)

    }

    private var lastToggle = Date.distantPast

    func toggle() {
        // 全局热键与本地按键可能在同一瞬间各触发一次，这里做去抖
        let now = Date()
        if now.timeIntervalSince(lastToggle) < 0.35 { return }
        lastToggle = now
        if isActive { finish() } else { start() }
    }

    func finish(quiet: Bool = false) {
        guard isActive else { return }
        views.forEach { $0.commitPendingEdit() }

        if Prefs.autoScreenshot {
            for st in canvases { Exporter.autoScreenshot(st) }
        }

        isActive = false
        model.isActive = false
        magnifier?.orderOut(nil)
        magnifier = nil
        toast?.orderOut(nil)
        toast = nil
        teardownWindows()

        if Prefs.quitOnFinish {
            NSApp.terminate(nil)
            return
        }
        SettingsWindowController.shared.adaptToSession()
        GlobalHotKey.shared.registerCurrent()      // 恢复全局热键
        startPanel?.orderFrontRegardless()
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate(options: [])
        } else {
            NSApp.deactivate()
        }
        _ = quiet
    }

    private func teardownWindows() {
        views.forEach { $0.removeFromSuperview() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        hostingView = nil
        canvases.removeAll()
        activeIndex = 0
    }

    // MARK: 工具栏

    private func showToolbar() {
        let model = self.model
        let view = ToolbarView(model: model, controller: self)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 150, height: 700)
        let panel = ToolbarPanel(contentRect: hosting.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(140, fit.width), height: max(200, fit.height)))

        let screen = activeCanvas?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        var origin = Prefs.toolbarOrigin()
        if origin == nil {
            origin = NSPoint(x: screen.frame.maxX - panel.frame.width - 24,
                             y: screen.frame.maxY - panel.frame.height - 60)
        }
        if let o = origin {
            let clamped = clampToScreens(NSRect(origin: o, size: panel.frame.size))
            panel.setFrameOrigin(clamped.origin)
        }
        panel.orderFrontRegardless()
        toolbarPanel = panel
        hostingView = hosting
    }

    private func clampToScreens(_ r: NSRect) -> NSRect {
        var rect = r
        let inside = NSScreen.screens.contains { $0.frame.intersects(rect) }
        if !inside, let f = NSScreen.screens.first {
            rect.origin = NSPoint(x: f.frame.maxX - rect.width - 24, y: f.frame.maxY - rect.height - 60)
        }
        return rect
    }

    func toolbarFrameChanged(to origin: NSPoint) {
        Prefs.setToolbarOrigin(origin)
    }

    func toolbarPanelFrame() -> NSRect? { toolbarPanel?.frame }

    func allViews() -> [CanvasView] { views }

    // MARK: 覆盖层挂起（显示系统对话框时必须，否则对话框会被冻结层盖住）

    private var suspended = false

    func suspendOverlays() {
        guard isActive, !suspended else { return }
        suspended = true
        windows.forEach { $0.orderOut(nil) }
        toolbarPanel?.orderOut(nil)
        magnifier?.orderOut(nil)
    }

    func resumeOverlays() {
        guard isActive, suspended else { return }
        suspended = false
        windows.forEach { $0.orderFrontRegardless() }
        toolbarPanel?.orderFrontRegardless()
        makeCanvasKey()
    }

    func withSuspendedOverlays<T>(_ body: () -> T) -> T {
        suspendOverlays()
        let r = body()
        resumeOverlays()
        return r
    }

    func rebuildToolbar() {
        guard isActive else { return }
        let origin = toolbarPanel?.frame.origin
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        hostingView = nil
        showToolbar()
        if let o = origin { toolbarPanel?.setFrameOrigin(o) }
    }

    func commitPendingEdit() { views.forEach { $0.commitPendingEdit() } }

    /// 滚轮缩放时同步当前工具状态
    func zoomToolSync(zoomed: Bool) {
        if zoomed {
            if tool != .zoomIn && tool != .zoomOut { previousTool = tool }
            tool = .zoomIn
        } else {
            tool = previousTool
        }
        syncModel()
        views.forEach { $0.refreshCursor(); $0.needsDisplay = true }
    }

    func makeCanvasKey() {
        guard windows.indices.contains(activeIndex), views.indices.contains(activeIndex) else { return }
        windows[activeIndex].makeKeyAndOrderFront(nil)
        windows[activeIndex].makeFirstResponder(views[activeIndex])
    }

    func moveToolbar(by delta: CGSize) {
        guard let p = toolbarPanel else { return }
        var o = p.frame.origin
        o.x += delta.width
        o.y -= delta.height
        p.setFrameOrigin(o)
        Prefs.setToolbarOrigin(o)
    }

    func syncModel() {
        model.tool = tool
        model.swatchIndex = swatchIndex
        model.penSizeIndex = penSizeIndex
        model.swatches = Palette.all
        model.zoomFactor = activeCanvas?.zoom ?? 1
        model.canUndo = !(activeCanvas?.strokes.isEmpty ?? true)
        model.hasStrokes = model.canUndo
        model.hasRegion = activeCanvas?.region != nil
        model.screenName = activeCanvas?.screen.localizedName ?? ""
    }

    func onToolChanged() {
        syncModel()
        views.forEach { $0.refreshCursor() }
    }

    func setActive(_ st: CanvasState) {
        guard let idx = canvases.firstIndex(where: { $0 === st }) else { return }
        if idx != activeIndex {
            activeIndex = idx
            syncModel()
        }
    }

    func canvasMouseMoved(canvas: CanvasState, localPoint: CGPoint, view: CanvasView, event: NSEvent) {
        if let idx = canvases.firstIndex(where: { $0 === canvas }), idx != activeIndex {
            activeIndex = idx
            syncModel()
        }
        if tool == .magnifier, let m = magnifier {
            m.update(canvas: canvas, at: localPoint, penSize: penSize)
        }
    }

    func didChangeStrokes(_ st: CanvasState) {
        st.invalidateZoomCache()
        syncModel()
    }

    func flashStatus(_ s: String) {
        if toast == nil { toast = ToastPanel() }
        toast?.show(s)
    }

    // MARK: 工具与颜色

    func setTool(_ t: ToolKind) {
        guard let st = activeCanvas else { return }
        if t == .zoomOut || t == .zoomIn {
            zoom(canvas: st, direction: t == .zoomIn ? 1 : -1, center: nil)
            return
        }
        if st.isZoomed && !t.worksWhileZoomed {
            // 绘图类工具：先退出缩放视图再启用（原版在缩放视图内禁止绘图）
            views.forEach { $0.enterZoom(1, center: nil) }
            st.zoom = 1
        }
        applyTool(t, silent: false)
    }

    private func applyTool(_ t: ToolKind, silent: Bool) {
        if t != .zoomIn && t != .zoomOut { previousTool = t }
        tool = t
        if t != .magnifier {
            magnifier?.orderOut(nil)
        } else if let st = activeCanvas,
                  let v = views.first(where: { $0.state === st }), v.hasMousePoint {
            // 选中放大镜后立刻显示，不必先移动鼠标
            magnifier?.update(canvas: st, at: v.mousePointValue, penSize: penSize)
        }
        Prefs.lastTool = t
        views.forEach { $0.refreshCursor(); $0.needsDisplay = true }
        if !silent { syncModel() } else { syncModel() }
    }

    func setSwatch(_ i: Int) {
        swatchIndex = min(max(0, i), Palette.all.count - 1)
        Prefs.lastSwatch = swatchIndex
        syncModel()
    }

    func setPenSize(_ i: Int) {
        penSizeIndex = PenSize.clamp(i)
        Prefs.lastPenSize = penSizeIndex
        syncModel()
        views.forEach { $0.refreshCursor() }
        magnifier?.applyPenSize(penSize)
    }

    // MARK: 缩放

    func zoom(canvas: CanvasState, direction: Int, center: CGPoint?) {
        let steps: [CGFloat] = [1, 2, 3, 4, 5, 6, 8, 10]
        let current = steps.firstIndex(where: { $0 >= canvas.zoom - 0.001 }) ?? 0
        let next = min(max(0, current + direction), steps.count - 1)
        if steps[next] <= 1 {
            views.forEach { $0.enterZoom(1, center: center) }
            canvas.zoom = 1
            applyTool(previousTool, silent: false)
        } else {
            // 缩放视图：先合成当前画面
            canvas.invalidateZoomCache()
            views.forEach { v in
                if v.state === canvas { v.enterZoom(steps[next], center: center) }
            }
            if tool != .zoomIn && tool != .zoomOut { previousTool = tool }
            tool = .zoomIn
            syncModel()
            views.forEach { $0.refreshCursor() }
        }
    }

    // MARK: 动作

    func undo() {
        guard let st = activeCanvas, !st.strokes.isEmpty else { return }
        st.strokes.removeLast()
        st.rebuild()
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func clearAll() {
        guard let st = activeCanvas else { return }
        st.strokes.removeAll()
        st.layer.clear()
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func setBackground(_ k: BackgroundKind) {
        guard let st = activeCanvas else { return }
        if k == .clipboard {
            guard let img = Exporter.imageFromClipboard() else {
                flashStatus(LS("Zwischenablage enthält kein Bild", "Clipboard has no image", "剪贴板里没有图片", "剪貼簿裡沒有圖片"))
                return
            }
            st.clipboardCG = img
            st.clipboardSize = CGSize(width: CGFloat(img.width) / st.scale, height: CGFloat(img.height) / st.scale)
            st.clipboardSize = CGSize(width: min(st.clipboardSize.width, st.pointSize.width),
                                      height: min(st.clipboardSize.height, st.pointSize.height))
        }
        st.background = k
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
    }

    func pasteFromClipboard() { setBackground(.clipboard) }

    // MARK: 键盘

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard isActive, event.modifierFlags.contains(.command) else { return false }
        // 全局热键在会话中已注销，这里接管它，否则无法用热键结束会话
        if Prefs.hotKeySpec.matches(event) { finish(); return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "z":
            if event.modifierFlags.contains(.shift) { undo() } else { undo() }
            return true
        case "c": Exporter.copyToClipboard(activeCanvas); return true
        case "v": pasteFromClipboard(); return true
        case "s", "u": Exporter.saveWithPanel(activeCanvas, screen: activeCanvas?.screen); return true
        case "+", "=":
            if let st = activeCanvas { zoom(canvas: st, direction: 1, center: nil) }
            return true
        case "-", "_":
            if let st = activeCanvas { zoom(canvas: st, direction: -1, center: nil) }
            return true
        case "p": Exporter.print(activeCanvas); return true
        case "o": Exporter.openScreenshotFolder(); return true
        case "e": Exporter.composeMail(activeCanvas, openFolderFirst: true); return true
        case "a": return false
        default: return false
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        // 功能键（F1–F20）不经过 performKeyEquivalent，在这里匹配
        if Prefs.hotKeySpec.matches(event) { finish(); return true }
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 101: // F9
            finish(); return true
        case 98, 100: // F7 / F8 —— 原版的存档键
            Exporter.saveWithPanel(activeCanvas, screen: activeCanvas?.screen); return true
        case 120: // F2 选区精确输入
            if tool == .region { RegionCoordDialog.show(controller: self); return true }
            return false
        case 53: // ESC
            if let st = activeCanvas, st.isZoomed { views.forEach { $0.enterZoom(1, center: nil) }; applyTool(previousTool, silent: false); return true }
            finish(); return true
        case 123, 124, 125, 126: // 方向键移动选区
            guard tool == .region, activeCanvas?.region != nil else { return false }
            let step: CGFloat = shift ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
            let dy: CGFloat = event.keyCode == 125 ? step : (event.keyCode == 126 ? -step : 0)
            views.forEach { $0.moveRegionBy(dx: dx, dy: dy) }
            return true
        default: break
        }

        guard !cmd else { return false }
        guard let ch = event.charactersIgnoringModifiers?.lowercased(), !ch.isEmpty else { return false }
        switch ch {
        case "b": setTool(.pen); return true
        case "e": setTool(.eraser); return true
        case "g": setTool(.line); return true
        case "p": setTool(.arrow); return true
        case "d": setTool(.doubleArrow); return true
        case "r": setTool(shift ? .rectFilled : .rect); return true
        case "o": setTool(shift ? .ellipseFilled : .ellipse); return true
        case "t": setTool(.text); return true
        case "h": setTool(.check); return true
        case "k": setTool(.cross); return true
        case "f": setTool(.region); return true
        case "m": setTool(.magnifier); return true
        case "+", "=":
            if let st = activeCanvas { zoom(canvas: st, direction: 1, center: nil) }
            return true
        case "-", "_":
            if let st = activeCanvas { zoom(canvas: st, direction: -1, center: nil) }
            return true
        case "1", "2", "3", "4":
            if let n = Int(ch) { setPenSize(n - 1) }
            return true
        default: return false
        }
    }

    // MARK: 右键菜单

    func showContextMenu(at point: CGPoint, in view: CanvasView, event: NSEvent) {
        let menu = buildMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false

        func add(_ title: String, _ sel: Selector?, _ key: String = "", _ target: AnyObject = SessionController.shared) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = target
            m.addItem(it)
        }

        for t in [ToolKind.pen, .eraser, .line, .arrow, .doubleArrow, .rect, .rectFilled,
                  .ellipse, .ellipseFilled, .text, .check, .cross, .region, .magnifier] {
            let it = NSMenuItem(title: "\(t.title)   (\(t.shortcutHint))", action: #selector(menuTool(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t.rawValue
            it.state = (tool == t) ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        add(LS("Hineinzoomen (+)","Zoom in (+)","放大视图 (+)", "放大檢視 (+)"), #selector(menuZoomIn))
        add(LS("Herauszoomen (−)","Zoom out (−)","缩小视图 (−)", "縮小檢視 (−)"), #selector(menuZoomOut))
        m.addItem(.separator())
        add(LS("Rückgängig (⌘Z)","Undo (⌘Z)","撤销 (⌘Z)", "復原 (⌘Z)"), #selector(menuUndo), "z")
        add(LS("Alles löschen","Clear all","清空标注", "清空標註"), #selector(menuClear))
        m.addItem(.separator())
        add(LS("Kopieren (⌘C)","Copy (⌘C)","复制到剪贴板 (⌘C)", "複製到剪貼簿 (⌘C)"), #selector(menuCopy), "c")
        add(LS("Speichern (⌘S)","Save (⌘S)","保存图片 (⌘S)", "儲存圖片 (⌘S)"), #selector(menuSave), "s")
        add(LS("Drucken (⌘P)","Print (⌘P)","打印 (⌘P)", "列印 (⌘P)"), #selector(menuPrint), "p")
        add(LS("Per E-Mail senden (⌘E)","Send by e-mail (⌘E)","邮件发送 (⌘E)", "郵件傳送 (⌘E)"), #selector(menuMail), "e")
        m.addItem(.separator())
        add(LS("Fertig (F9)","Finish (F9)","完成 (F9)", "完成 (F9)"), #selector(menuFinish))
        return m
    }

    @objc private func menuTool(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let t = ToolKind(rawValue: raw) { setTool(t) }
    }
    @objc private func menuZoomIn() { if let st = activeCanvas { zoom(canvas: st, direction: 1, center: nil) } }
    @objc private func menuZoomOut() { if let st = activeCanvas { zoom(canvas: st, direction: -1, center: nil) } }
    @objc private func menuUndo() { undo() }
    @objc private func menuClear() { clearAll() }
    @objc private func menuCopy() { Exporter.copyToClipboard(activeCanvas) }
    @objc private func menuSave() { Exporter.saveWithPanel(activeCanvas, screen: activeCanvas?.screen) }
    @objc private func menuPrint() { Exporter.print(activeCanvas) }
    @objc private func menuMail() { Exporter.composeMail(activeCanvas, openFolderFirst: true) }
    @objc private func menuFinish() { finish() }
}

// MARK: - 启动按钮小窗

final class StartButtonPanel: NSPanel {
    private var onClick: (() -> Void)?

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(contentRect: NSRect(x: 0, y: 0, width: 150, height: 62),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 62))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.22, blue: 0.38, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(srgbRed: 0.45, green: 0.6, blue: 0.95, alpha: 0.9).cgColor

        let title = NSTextField(labelWithString: Brand.name)
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = NSColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 1)
        title.frame = NSRect(x: 10, y: 40, width: 100, height: 16)
        container.addSubview(title)

        let badge = NSTextField(labelWithString: "⌘ Mac")
        badge.font = .systemFont(ofSize: 10, weight: .medium)
        badge.textColor = NSColor(srgbRed: 0.6, green: 0.72, blue: 0.95, alpha: 1)
        badge.frame = NSRect(x: 96, y: 41, width: 48, height: 14)
        badge.alignment = .right
        container.addSubview(badge)

        let btn = NSButton(title: LS("Start", "Start", "开始", "開始"), target: self, action: #selector(clicked))
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.frame = NSRect(x: 10, y: 8, width: 130, height: 28)
        btn.keyEquivalent = ""
        container.addSubview(btn)
        contentView = container
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                               object: self, queue: .main) { [weak self] _ in
            if let o = self?.frame.origin { Prefs.setStartOrigin(o) }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func clicked() { onClick?() }

    func placeAtSavedOrDefault() {
        if let o = Prefs.startOrigin() { setFrameOrigin(o); return }
        if let s = NSScreen.main {
            setFrameOrigin(NSPoint(x: s.frame.maxX - frame.width - 40, y: s.frame.minY + 80))
        }
    }
}

// MARK: - 选区精确坐标输入（F2）

enum RegionCoordDialog {
    static func show(controller: SessionController) {
        guard let st = controller.activeCanvas else { return }
        let r = st.region ?? CGRect(x: 0, y: 0, width: st.pointSize.width, height: st.pointSize.height)
        let alert = NSAlert()
        alert.messageText = LS("Bildbereich festlegen", "Set image region", "设定选区", "設定選取範圍")
        alert.informativeText = LS("Position und Größe in Pixeln", "Position and size in pixels", "位置与尺寸（像素）", "位置與尺寸（像素）")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: LS("Abbrechen", "Cancel", "取消", "取消"))

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 62))
        func field(_ label: String, _ value: CGFloat, _ x: CGFloat, _ y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: label)
            l.frame = NSRect(x: x, y: y + 2, width: 16, height: 18)
            box.addSubview(l)
            let f = NSTextField(frame: NSRect(x: x + 18, y: y, width: 70, height: 22))
            f.stringValue = String(Int(value.rounded()))
            box.addSubview(f)
            return f
        }
        let s = st.scale
        let fx = field("X", r.minX * s, 0, 32)
        let fy = field("Y", r.minY * s, 110, 32)
        let fw = field("B", r.width * s, 0, 2)
        let fh = field("H", r.height * s, 110, 2)

        alert.accessoryView = box
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        if controller.withSuspendedOverlays({ alert.runModal() }) == .alertFirstButtonReturn {
            let x = (Double(fx.stringValue) ?? 0) / Double(s)
            let y = (Double(fy.stringValue) ?? 0) / Double(s)
            let w = (Double(fw.stringValue) ?? 0) / Double(s)
            let h = (Double(fh.stringValue) ?? 0) / Double(s)
            st.region = CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
            for v in controller.allViews() { v.needsDisplay = true }
        }
        controller.makeCanvasKey()
    }
}
