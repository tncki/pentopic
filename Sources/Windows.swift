// Windows.swift — 覆盖窗口 / 工具栏面板 / 放大镜 / 会话控制器
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - 延时捕捉倒计时

/// 延时捕捉时显示的倒计时浮窗。用来截「打开的下拉菜单」这类需要先摆好界面的场景。
final class CountdownPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.88).cgColor
        box.layer?.cornerRadius = 20
        box.layer?.borderWidth = 2
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        label.frame = NSRect(x: 0, y: 22, width: 120, height: 76)
        box.addSubview(label)
        contentView = box
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func run(seconds: Int, then completion: @escaping () -> Void) {
        var remaining = seconds
        label.stringValue = "\(remaining)"
        if let scr = NSScreen.main {
            setFrameOrigin(NSPoint(x: scr.frame.midX - 60, y: scr.frame.midY - 60))
        }
        orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                self?.orderOut(nil)
                completion()
            } else {
                self?.label.stringValue = "\(remaining)"
            }
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        orderOut(nil)
    }
}

// MARK: - 悬停提示（自绘）
//
// SwiftUI 的 .help() 在 nonactivatingPanel（工具栏就是）里不会弹出，
// 所以自己做一个跟随鼠标的小浮层。
final class TooltipPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 26),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 26))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.94).cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        label.frame = NSRect(x: 8, y: 5, width: 104, height: 16)
        label.autoresizingMask = [.width]
        box.addSubview(label)
        contentView = box
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ text: String) {
        guard !text.isEmpty else { hide(); return }
        label.stringValue = text
        let size = (text as NSString).size(withAttributes: [.font: label.font as Any])
        let w = min(420, size.width + 22), h: CGFloat = 26
        setContentSize(NSSize(width: w, height: h))
        contentView?.frame = NSRect(x: 0, y: 0, width: w, height: h)
        label.frame = NSRect(x: 8, y: 5, width: w - 16, height: 16)
        let m = NSEvent.mouseLocation
        // 放在光标右下，靠边时翻到另一侧
        var x = m.x + 14, y = m.y - h - 14
        if let scr = NSScreen.screens.first(where: { $0.frame.contains(m) }) {
            if x + w > scr.frame.maxX { x = m.x - w - 14 }
            if y < scr.frame.minY { y = m.y + 14 }
        }
        setFrameOrigin(NSPoint(x: x, y: y))
        if !isVisible { orderFrontRegardless() }
    }

    func hide() { orderOut(nil) }
}

// MARK: - 取色面板

final class ColorInfoPanel: NSPanel {
    private let swatch = NSView()
    private let hexLabel = NSTextField(labelWithString: "")
    private let rgbLabel = NSTextField(labelWithString: "")
    private let hslLabel = NSTextField(labelWithString: "")
    private var currentHex = "#000000"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 190, height: 78),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 190, height: 78))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.95).cgColor
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        swatch.frame = NSRect(x: 10, y: 12, width: 54, height: 54)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        box.addSubview(swatch)

        let hint = NSTextField(labelWithString: LS("Klicken = kopieren", "Click = copy", "点击复制", "點擊複製"))
        hint.font = .systemFont(ofSize: 9)
        hint.textColor = NSColor.white.withAlphaComponent(0.5)
        hint.frame = NSRect(x: 10, y: 2, width: 60, height: 12)
        box.addSubview(hint)

        for (i, f) in [hexLabel, rgbLabel, hslLabel].enumerated() {
            f.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            f.textColor = .white
            f.frame = NSRect(x: 74, y: 52 - CGFloat(i) * 18, width: 108, height: 15)
            box.addSubview(f)
        }
        contentView = box
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ color: NSColor, at screenPoint: NSPoint) {
        let c = color.usingColorSpace(.sRGB) ?? color
        currentHex = c.hexString
        swatch.layer?.backgroundColor = c.cgColor
        let r = Int(round(c.redComponent * 255)), g = Int(round(c.greenComponent * 255)), b = Int(round(c.blueComponent * 255))
        hexLabel.stringValue = currentHex
        rgbLabel.stringValue = "R \(r)  G \(g)  B \(b)"
        // HSL
        let rf = c.redComponent, gf = c.greenComponent, bf = c.blueComponent
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf)
        let l = (mx + mn) / 2
        var h: CGFloat = 0, sat: CGFloat = 0
        if mx != mn {
            let d = mx - mn
            sat = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == rf { h = (gf - bf) / d + (gf < bf ? 6 : 0) }
            else if mx == gf { h = (bf - rf) / d + 2 }
            else { h = (rf - gf) / d + 4 }
            h /= 6
        }
        hslLabel.stringValue = String(format: "H %.0f°  S %.0f%%  L %.0f%%", h * 360, sat * 100, l * 100)

        var origin = NSPoint(x: screenPoint.x + 18, y: screenPoint.y - 90)
        if let scr = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) {
            if origin.x + 190 > scr.frame.maxX { origin.x = screenPoint.x - 208 }
            if origin.y < scr.frame.minY { origin.y = screenPoint.y + 18 }
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    /// 点击面板 = 复制 HEX。用本地点击监视器实现（面板自身不接收鼠标事件时也能用）。
    func copyCurrent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentHex, forType: .string)
    }
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
    @Published var canRedo = false
    @Published var selectedCount = 0
    var hasSelection: Bool { selectedCount > 0 }
    var hasMultiSelection: Bool { selectedCount > 1 }
    var isSelecting: Bool { tool == .select }
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
    private var tooltip: TooltipPanel?
    private var countdown: CountdownPanel?
    private var colorInfo: ColorInfoPanel?
    private var toast: ToastPanel?
    private var startPanel: StartButtonPanel?

    /// 因为切到别的 App 而临时收起（会话本身还在，标注一条都不会丢）
    private(set) var hiddenForAppSwitch = false
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
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

        // 延时捕捉：先把界面让给用户摆好（比如展开一个菜单），倒计时结束再冻结
        let delay = synchronously ? 0 : Prefs.captureDelay
        if delay > 0 {
            if countdown == nil { countdown = CountdownPanel() }
            countdown?.run(seconds: delay) { [weak self] in
                self?.performStart(synchronously: synchronously)
            }
            return
        }
        performStart(synchronously: synchronously)
    }

    private func performStart(synchronously: Bool) {
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

    /// 一块画布的构建参数。整屏捕捉时 rect == screen.frame；
    /// 「裁剪到选区」和「窗口捕捉」会用更小的 rect。
    struct CanvasSpec {
        let screen: NSScreen
        let image: CGImage?
        let rect: CGRect
        var strokes: [Stroke] = []
    }

    private func buildSession(screens: [NSScreen], captured: [CGDirectDisplayID: CapturedScreen]) {
        buildSession(specs: screens.map {
            CanvasSpec(screen: $0,
                       image: captured[ScreenCapture.displayID(of: $0)]?.cgImage,
                       rect: $0.frame)
        })
    }

    private func buildSession(specs: [CanvasSpec]) {
        teardownWindows()
        canvases.removeAll()
        var target: CanvasState?

        for spec in specs {
            let screen = spec.screen
            guard let st = CanvasState(screen: screen, image: spec.image,
                                       rect: spec.rect, scale: screen.backingScaleFactor) else { continue }
            if !spec.strokes.isEmpty {
                for s in spec.strokes { st.layer.apply(s) }
                st.strokes = spec.strokes
            }
            let view = CanvasView(state: st, controller: self)

            let w = OverlayWindow(contentRect: spec.rect, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.acceptsMouseMovedEvents = true
            w.isReleasedWhenClosed = false
            w.contentView = view
            w.setFrame(spec.rect, display: true)
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

        enterSessionActivation()
        showToolbar()
        magnifier = MagnifierPanel()
        toast = ToastPanel()
        SettingsWindowController.shared.adaptToSession()
        // 每次开新会话都回到用户设定的初始工具。
        // 默认是指针：刚冻结屏幕时最可能先做的事是看看、挪一挪已有的标记，
        // 而不是立刻落笔；指针也不会因为误拖而在画面上留下东西。
        applyTool(Prefs.initialTool, silent: true)
        syncModel()

    }

    private var lastToggle = Date.distantPast

    func toggle() {
        // 全局热键与本地按键可能在同一瞬间各触发一次，这里做去抖
        let now = Date()
        if now.timeIntervalSince(lastToggle) < 0.35 { return }
        lastToggle = now
        // 切走之后的"回到标注"也应该能被热键唤起，而不是把会话结束掉
        if hiddenForAppSwitch { resumeAfterAppSwitch(); return }
        if isActive { finish() } else { start() }
    }

    func finish(quiet: Bool = false) {
        guard isActive else { return }
        views.forEach { $0.commitPendingEdit() }

        // 捕捉历史：无论用户是否落了盘，都先留一份。
        // 但**必须排除 quiet 路径** —— 那是捕捉失败/权限未生效时的兜底清理，
        // 早期版本没排除，结果一次失败的捕捉也会往历史里塞一张空白图。
        // 同样要求真的有底图，否则记下来的只是白板。
        if !quiet, Prefs.historyEnabled {
            for st in canvases where st.frozenCG != nil {
                if let img = st.composeCG() { CaptureHistory.record(img) }
            }
        }

        if Prefs.autoScreenshot {
            for st in canvases { Exporter.autoScreenshot(st) }
        }

        isActive = false
        hiddenForAppSwitch = false
        leaveSessionActivation()
        model.isActive = false
        dismissFloatingPanels()
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

    /// 收起"跟着按钮走"的提示浮窗。
    /// 工具栏重建后按钮对象已销毁，提示若还在就会悬空 —— 只收这一个。
    private func dismissTooltip() {
        tooltip?.hide()
        tooltip = nil
    }

    /// 收起会话期间创建的**全部**浮窗，会话结束（或提前失败）时调用。
    ///
    /// ⚠️ **新增浮窗时必须加到这里**。之前就漏了取色面板和悬停提示 ——
    /// 结束会话后它们仍留在屏幕上（用户实测到的问题）。
    ///
    /// 注意区分：放大镜、提示条、取色面板都只在 `buildSession` 里创建一次，
    /// 所以**只有会话结束才该销毁它们**。早先把本方法接到 `rebuildToolbar` 上，
    /// 结果会话中途改一次形状分配就把放大镜永久置空了（测试抓到的回归）。
    private func dismissFloatingPanels() {
        countdown?.cancel();      countdown = nil
        magnifier?.orderOut(nil); magnifier = nil
        toast?.orderOut(nil);     toast = nil
        colorInfo?.orderOut(nil); colorInfo = nil
        dismissTooltip()
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
        // 空白处也能拖动整个工具栏。按钮会自己消费点击，只有按钮之间的空隙
        // 会触发窗口拖动 —— 工具栏这么高，只能从细窄的标题栏拖太不方便。
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(140, fit.width), height: max(200, fit.height)))

        let screen = activeCanvas?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let desired = Prefs.toolbarOrigin() ?? NSPoint(
            x: screen.visibleFrame.maxX - panel.frame.width - 24,
            y: screen.visibleFrame.maxY - panel.frame.height - 60)
        let clamped = clampToScreens(NSRect(origin: desired, size: panel.frame.size))
        panel.setFrameOrigin(clamped.origin)
        Prefs.setToolbarOrigin(clamped.origin)      // 存回钳制后的位置
        panel.orderFrontRegardless()
        toolbarPanel = panel
        hostingView = hosting
    }

    /// 把窗口完整放进某块屏幕的**可见区域**。
    ///
    /// 早先只判断"是否和任意屏幕相交"，部分露出屏幕时完全不调整 ——
    /// 工具栏长出屏幕外时，顶部那块拖动柄就够不到了。
    /// 用 visibleFrame 而不是 frame：后者包含菜单栏和 Dock。
    private func clampToScreens(_ r: NSRect) -> NSRect {
        func overlap(_ f: CGRect) -> CGFloat {
            let i = f.intersection(r)
            return i.isNull ? 0 : i.width * i.height
        }
        let screen = NSScreen.screens.max { overlap($0.frame) < overlap($1.frame) } ?? NSScreen.main
        guard let s = screen else { return r }
        let vis = s.visibleFrame
        var rect = r
        rect.origin.x = min(max(rect.origin.x, vis.minX), max(vis.minX, vis.maxX - rect.width))
        if rect.height >= vis.height {
            rect.origin.y = vis.maxY - rect.height      // 比屏幕还高：先保顶部（拖动柄）
        } else {
            rect.origin.y = min(max(rect.origin.y, vis.minY), vis.maxY - rect.height)
        }
        return rect
    }

    func toolbarFrameChanged(to origin: NSPoint) {
        Prefs.setToolbarOrigin(origin)
    }

    func toolbarPanelFrame() -> NSRect? { toolbarPanel?.frame }

    /// 自检用
    var toolbarPanelForTest: ToolbarPanel? { toolbarPanel }
    var overlayWindowsForTest: [NSWindow] { windows }
    func clampForTest(_ r: NSRect) -> NSRect { clampToScreens(r) }

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
        dismissTooltip()             // 旧按钮已销毁，提示要跟着收；放大镜等会话级浮窗不能动
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
        model.canUndo = activeCanvas?.canUndo ?? false
        model.canRedo = activeCanvas?.canRedo ?? false
        // 用实际存在的选中笔画数，而不是 id 集合的大小（可能有悬空引用）；
        // 且只在指针工具下才算"有选择" —— 别的工具下选择不可见也不可操作。
        if let st = activeCanvas { st.pruneSelection() }
        model.selectedCount = tool == .select ? (activeCanvas?.selectedStrokes.count ?? 0) : 0
        model.hasStrokes = !(activeCanvas?.strokes.isEmpty ?? true)
        model.hasRegion = activeCanvas.map { $0.region != nil || $0.regionPath != nil } ?? false
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

    // MARK: 悬停提示

    /// SwiftUI 的 .help() 在 nonactivatingPanel 里不弹，所以自己控制
    func showTooltip(_ text: String?) {
        if let t = text, !t.isEmpty {
            if tooltip == nil { tooltip = TooltipPanel() }
            tooltip?.show(t)
        } else {
            tooltip?.hide()
        }
    }

    // MARK: 界面自定义（右键菜单调用）

    /// 把某个形状槽位换成另一个形状
    func assignShapeSlot(_ slot: Int, to tool: ToolKind) {
        var slots = Prefs.effectiveShapeSlots
        guard slot < slots.count else { return }
        slots[slot] = tool
        Prefs.shapeSlots = slots.map { $0.rawValue }
        rebuildToolbar()
        syncModel()
    }

    func setNumberShape(_ shape: NumberShape) {
        Prefs.numberShape = shape
        rebuildToolbar()
        flashStatus(LS("Markierungsform: \(shape.title)", "Marker shape: \(shape.title)",
                       "序号形状：\(shape.title)", "序號形狀：\(shape.title)"))
    }

    /// 用系统颜色面板给某个颜色槽位选新颜色
    func pickColorForSlot(_ index: Int) {
        let current = Palette.all.indices.contains(index) ? Palette.all[index].color.hexString : "#FF0000"
        ColorPanelBridge.shared.pick(from: current) { [weak self] hex in
            self?.setPaletteSlot(index, to: hex)
        }
    }

    func setPaletteSlot(_ index: Int, to hex: String) {
        Palette.setSlot(index, hex: hex)
        rebuildToolbar()
        syncModel()
    }

    // MARK: 取色

    func sampleColor(canvas st: CanvasState, at point: CGPoint) {
        guard let img = st.composeCG(),
              let col = PixelSampler.color(of: img, at: CGPoint(x: point.x * st.scale, y: point.y * st.scale)) else { return }
        if colorInfo == nil { colorInfo = ColorInfoPanel() }
        colorInfo?.show(col, at: NSEvent.mouseLocation)
        // 取色即复制，符合"吸管"的直觉
        colorInfo?.copyCurrent()
        flashStatus(LS("Farbe \(col.hexString) kopiert", "Colour \(col.hexString) copied", "已复制颜色 \(col.hexString)", "已複製顏色 \(col.hexString)"))
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

    /// 供布局重置调用（applyTool 是私有的）
    func applyToolPublic(_ t: ToolKind) { applyTool(t, silent: false) }

    // MARK: 自检钩子
    var modelSelectedCount: Int { model.selectedCount }
    func handleKeyDownForTest(keyCode: UInt16) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       characters: "", charactersIgnoringModifiers: "",
                                       isARepeat: false, keyCode: keyCode) else { return false }
        return handleKeyDown(e)
    }

    /// 临时工具栈（空格 / ⇧拖动借用别的工具，松开还原）。
    /// 用栈而不是单个变量：空格和 ⇧拖动可能同时生效，嵌套也能正确还原。
    private var tempToolStack: [ToolKind] = []
    var isTemporaryTool: Bool { !tempToolStack.isEmpty }

    /// 临时切到某个工具（不改变"上次使用的工具"记忆）
    func pushTemporaryTool(_ t: ToolKind) {
        guard isActive, tool != t else { return }
        tempToolStack.append(tool)
        applyTool(t, silent: false, remember: false)
    }

    /// 还原临时切换
    func popTemporaryTool() {
        guard let back = tempToolStack.popLast() else { return }
        applyTool(back, silent: false, remember: false)
    }

    private func applyTool(_ t: ToolKind, silent: Bool, remember: Bool = true) {
        if remember, t != .zoomIn && t != .zoomOut { previousTool = t }
        tool = t
        if t != .magnifier {
            magnifier?.orderOut(nil)
        } else if let st = activeCanvas,
                  let v = views.first(where: { $0.state === st }), v.hasMousePoint {
            // 选中放大镜后立刻显示，不必先移动鼠标
            magnifier?.update(canvas: st, at: v.mousePointValue, penSize: penSize)
        }
        if remember { Prefs.lastTool = t }
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
        guard let st = activeCanvas, st.undoEdit() else { return }
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func redo() {
        guard let st = activeCanvas, st.redoEdit() else { return }
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func clearAll() {
        guard let st = activeCanvas else { return }
        st.beginEdit()
        st.strokes.removeAll()
        st.selection.removeAll()
        st.layer.clear()
        // clear 是直接抹图层，快照恢复后要重放一遍才对
        st.rebuild()
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
        // 打码是按"当时的底图"烘焙进标注层的，换底图后必须重放，
        // 否则会把旧底图的内容留在新底图上。
        st.rebuild()
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
    }

    func pasteFromClipboard() { setBackground(.clipboard) }

    // MARK: 用任意图像开启会话

    /// 用一张现成的图开启标注会话（窗口捕捉、历史回看都走这里）。
    /// - Parameter rect: 画布在屏幕坐标系里的位置与大小
    func startSession(withImage image: CGImage, rect: CGRect, completion: (() -> Void)? = nil) {
        guard !isActive else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        guard let screen else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        isActive = true
        model.isActive = true
        startPanel?.orderOut(nil)
        Prefs.ensureFolders()
        buildSession(specs: [CanvasSpec(screen: screen, image: image, rect: rect)])
        completion?()
    }

    // MARK: 窗口捕捉

    /// 抓取指定窗口，并直接以它为画布开启会话
    func captureWindow(id: CGWindowID) {
        let all = ScreenCapture.windows()
        guard let info = all.first(where: { $0.id == id }) else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(info.frame) } ?? NSScreen.main
        guard let screen else { return }
        let scale = screen.backingScaleFactor
        guard let img = ScreenCapture.captureWindow(id: id, scale: scale) else {
            Alert.error(LS("Fenster konnte nicht aufgenommen werden",
                           "Could not capture the window",
                           "无法抓取该窗口", "無法抓取該視窗"),
                        LS("Das Fenster ist möglicherweise geschlossen oder geschützt.",
                           "The window may be closed or protected.",
                           "该窗口可能已关闭或受保护。", "該視窗可能已關閉或受保護。"))
            return
        }
        let title = info.title
        startSession(withImage: img, rect: info.frame) {
            SessionController.shared.flashStatus(LS("Fenster aufgenommen: \(title)",
                                                    "Window captured: \(title)",
                                                    "已捕捉窗口：\(title)", "已捕捉視窗：\(title)"))
        }
    }

    // MARK: 切换 App（⌘Tab）

    /// 会话期间把 App 切到 `.regular`。
    ///
    /// `.accessory`（常驻状态栏、无 Dock 图标）的 App **不出现在 ⌘Tab 列表里** ——
    /// 用户 ⌘Tab 切走了就再也没法用 ⌘Tab 切回来，只能去点状态栏图标。
    /// 会话期间临时变成 `.regular`，Dock 和 ⌘Tab 都能找到它，
    /// 切回来时 `didBecomeActive` 自然会触发恢复。
    private func enterSessionActivation() {
        previousActivationPolicy = NSApp.activationPolicy()
        if previousActivationPolicy != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// 会话结束恢复常驻状态栏的形态
    private func leaveSessionActivation() {
        let back = previousActivationPolicy ?? .accessory
        if NSApp.activationPolicy() != back { NSApp.setActivationPolicy(back) }
        previousActivationPolicy = nil
    }

    /// 会话期间切到别的 App 时把冻结层收起来。
    ///
    /// 冻结遮罩在 `screenSaver` 层级，盖住一切 —— 不收起的话，用户 ⌘Tab 过去了
    /// 却仍然只看到冻结画面，表现得就像 ⌘Tab 没反应。
    /// 会话本身不动：笔画、撤销栈、选择全都保留。
    func suspendForAppSwitch() {
        guard isActive, !hiddenForAppSwitch else { return }
        hiddenForAppSwitch = true
        for w in windows { w.orderOut(nil) }
        toolbarPanel?.orderOut(nil)
        magnifier?.orderOut(nil)
        toast?.orderOut(nil)
        countdown?.orderOut(nil)
        colorInfo?.orderOut(nil)
        tooltip?.hide()
        if let f = toolbarPanel?.frame.origin { Prefs.setToolbarOrigin(f) }
    }

    /// 回到标注。
    ///
    /// 窗口重排**同步**做（状态立刻一致、可预测）；
    /// 只有 `NSApp.activate` 延后一拍 —— 本方法会被**菜单动作**（状态栏菜单还在跟踪）
    /// 和 **App 激活通知回调**调用，在这些时刻同步激活会撞进 AppKit 正在处理的
    /// 激活流程里。
    func resumeAfterAppSwitch() {
        guard isActive, hiddenForAppSwitch else { return }
        hiddenForAppSwitch = false
        for w in windows where !w.isVisible { w.orderFrontRegardless() }
        toolbarPanel?.orderFrontRegardless()
        if tool == .magnifier, let st = activeCanvas,
           let v = views.first(where: { $0.state === st }), v.hasMousePoint {
            if magnifier == nil { magnifier = MagnifierPanel() }
            magnifier?.update(canvas: st, at: v.mousePointValue, penSize: penSize)
        }
        if let v = views.first(where: { $0.state === activeCanvas }), let w = v.window, w.isVisible {
            w.makeFirstResponder(v)
        }
        syncModel()
        DispatchQueue.main.async {
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        }
        flashStatus(LS("Zurück zur Anmerkung", "Back to annotating", "已返回标注", "已返回標註"))
    }

    // MARK: 选择与排列

    enum AlignMode { case left, centerX, right, top, centerY, bottom }

    private func selectionChanged(_ st: CanvasState) {
        st.rebuild()
        st.invalidateZoomCache()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func selectAll() {
        guard let st = activeCanvas else { return }
        st.selection = Set(st.strokes.filter { !$0.isEraser }.map { $0.id })
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func clearSelection() {
        guard let st = activeCanvas else { return }
        st.selection.removeAll()
        views.forEach { $0.needsDisplay = true }
        syncModel()
    }

    func deleteSelection() {
        guard let st = activeCanvas, !st.selection.isEmpty else { return }
        let n = st.selection.count
        st.beginEdit()
        st.strokes.removeAll { st.selection.contains($0.id) }
        st.selection.removeAll()
        selectionChanged(st)
        flashStatus(LS("\(n) Objekt(e) gelöscht", "\(n) object(s) deleted",
                       "已删除 \(n) 个对象", "已刪除 \(n) 個物件"))
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let st = activeCanvas, !st.selection.isEmpty else { return }
        st.beginEdit()
        st.moveSelection(dx: dx, dy: dy)
        views.forEach { $0.needsDisplay = true }
    }

    /// 对齐。基准是选区整体的包围盒。
    func alignSelection(_ mode: AlignMode) {
        guard let st = activeCanvas, st.selection.count > 1, let box = st.selectionBounds else { return }
        var deltas: [UUID: CGPoint] = [:]
        for s in st.selectedStrokes {
            let b = s.shape.bounds
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch mode {
            case .left:    dx = box.minX - b.minX
            case .centerX: dx = box.midX - b.midX
            case .right:   dx = box.maxX - b.maxX
            case .top:     dy = box.minY - b.minY
            case .centerY: dy = box.midY - b.midY
            case .bottom:  dy = box.maxY - b.maxY
            }
            if abs(dx) > 0.01 || abs(dy) > 0.01 { deltas[s.id] = CGPoint(x: dx, y: dy) }
        }
        guard !deltas.isEmpty else { return }
        st.beginEdit()
        st.strokes = st.strokes.map { s in
            guard let d = deltas[s.id] else { return s }
            return s.translated(dx: d.x, dy: d.y)
        }
        selectionChanged(st)
    }

    /// 等距分布。首尾不动，中间的重新排布。
    func distributeSelection(horizontal: Bool) {
        guard let st = activeCanvas, st.selection.count > 2 else { return }
        let sel = st.selectedStrokes.sorted {
            horizontal ? $0.shape.bounds.midX < $1.shape.bounds.midX
                       : $0.shape.bounds.midY < $1.shape.bounds.midY
        }
        guard let first = sel.first, let last = sel.last else { return }
        let a = horizontal ? first.shape.bounds.midX : first.shape.bounds.midY
        let b = horizontal ? last.shape.bounds.midX : last.shape.bounds.midY
        let step = (b - a) / CGFloat(sel.count - 1)
        var deltas: [UUID: CGPoint] = [:]
        for (i, s) in sel.enumerated() where i > 0 && i < sel.count - 1 {
            let cur = horizontal ? s.shape.bounds.midX : s.shape.bounds.midY
            let want = a + step * CGFloat(i)
            deltas[s.id] = horizontal ? CGPoint(x: want - cur, y: 0) : CGPoint(x: 0, y: want - cur)
        }
        guard !deltas.isEmpty else { return }
        st.beginEdit()
        st.strokes = st.strokes.map { s in
            guard let d = deltas[s.id] else { return s }
            return s.translated(dx: d.x, dy: d.y)
        }
        selectionChanged(st)
    }

    /// 组合：组合内的笔画在选择和移动时视为一体
    func groupSelection() {
        guard let st = activeCanvas, st.selection.count > 1 else { return }
        let g = UUID()
        st.beginEdit()
        st.strokes = st.strokes.map { s in
            guard st.selection.contains(s.id) else { return s }
            var c = s; c.groupID = g; return c
        }
        selectionChanged(st)
        flashStatus(LS("\(st.selection.count) Objekte gruppiert", "Grouped \(st.selection.count) objects",
                       "已组合 \(st.selection.count) 个对象", "已組合 \(st.selection.count) 個物件"))
    }

    func ungroupSelection() {
        guard let st = activeCanvas else { return }
        let groups = Set(st.selectedStrokes.compactMap { $0.groupID })
        guard !groups.isEmpty else { return }
        st.beginEdit()
        st.strokes = st.strokes.map { s in
            guard let g = s.groupID, groups.contains(g) else { return s }
            var c = s; c.groupID = nil; return c
        }
        selectionChanged(st)
        flashStatus(LS("Gruppierung aufgehoben", "Ungrouped", "已取消组合", "已取消組合"))
    }

    /// 层级：把选中对象移到最前 / 最后
    func reorderSelection(toFront: Bool) {
        guard let st = activeCanvas, !st.selection.isEmpty else { return }
        let sel = st.strokes.filter { st.selection.contains($0.id) }
        let rest = st.strokes.filter { !st.selection.contains($0.id) }
        st.beginEdit()
        st.strokes = toFront ? rest + sel : sel + rest
        selectionChanged(st)
    }

    // MARK: 旋转画布

    /// 把整块画布旋转 90°：底图和所有笔画一起转，转完还能继续标注和撤销。
    /// 只转图不转笔画会让标注和图像错位，所以两者必须共用同一套坐标变换。
    func rotateCanvas(clockwise: Bool) {
        guard let st = activeCanvas else { return }
        let oldSize = st.pointSize
        guard oldSize.width > 1, oldSize.height > 1 else { return }
        let newSize = CGSize(width: oldSize.height, height: oldSize.width)

        let newImage: CGImage?
        if let src = st.frozenCG {
            guard let r = CanvasRenderer.rotate90(src, clockwise: clockwise) else { return }
            newImage = r
        } else {
            newImage = nil
        }
        let q = clockwise ? 1 : 3
        let rotated = st.strokes.map { Stroke(shape: $0.shape.rotated(canvasSize: oldSize, quarterTurns: q),
                                              color: $0.color, width: $0.width, isEraser: $0.isEraser) }
        // 保持左上角不动，尺寸对调
        let rect = CGRect(x: st.rect.minX, y: st.rect.minY, width: newSize.width, height: newSize.height)
        var spec = CanvasSpec(screen: st.screen, image: newImage, rect: rect)
        spec.strokes = rotated
        buildSession(specs: [spec])
        flashStatus(clockwise
            ? LS("Um 90° gedreht", "Rotated 90° clockwise", "已顺时针旋转 90°", "已順時針旋轉 90°")
            : LS("Um 90° gedreht", "Rotated 90° anticlockwise", "已逆时针旋转 90°", "已逆時針旋轉 90°"))
    }

    // MARK: 区域捕捉

    /// 把当前画布裁剪到选中的区域：只保留那一块，成为新的画布。
    /// 已有笔画会整体平移过去，所以裁剪后仍然可以继续编辑和撤销。
    func cropToRegion() {
        guard let st = activeCanvas else { return }
        // 自由手绘选区用多边形的包围盒来裁剪
        let r: CGRect
        if let path = st.regionPath, path.count >= 3 {
            let xs = path.map { $0.x }, ys = path.map { $0.y }
            r = CGRect(x: xs.min()!, y: ys.min()!,
                       width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        } else if let rect = st.region {
            r = rect
        } else {
            flashStatus(LS("Bitte zuerst mit dem Bereich-Werkzeug einen Bereich aufziehen.",
                           "Select a region with the region tool first.",
                           "请先用「选区」工具框出一块区域。",
                           "請先用「選取範圍」工具框出一塊區域。"))
            return
        }
        guard r.width > 16, r.height > 16 else {
            flashStatus(LS("Der Bereich ist zu klein.", "The region is too small.",
                           "选区太小了。", "選取範圍太小了。"))
            return
        }
        guard let frozen = st.frozenCG else {
            flashStatus(LS("Dieses Blatt hat kein Bild zum Zuschneiden.",
                           "This sheet has no image to crop.",
                           "当前画板没有可裁剪的底图。",
                           "當前畫板沒有可裁剪的底圖。"))
            return
        }
        let px = CGRect(x: r.minX * st.scale, y: r.minY * st.scale,
                        width: r.width * st.scale, height: r.height * st.scale).integral
        guard let sub = frozen.cropping(to: px) else { return }

        // 区域的局部坐标 → 屏幕坐标
        let screenRect = CGRect(x: st.rect.minX + r.minX, y: st.rect.minY + r.minY,
                                width: r.width, height: r.height)
        let shifted = st.strokes.map { $0.translated(dx: -r.minX, dy: -r.minY) }

        buildSession(specs: [CanvasSpec(screen: st.screen, image: sub,
                                        rect: screenRect, strokes: shifted)])
        flashStatus(LS("Auf Auswahl zugeschnitten", "Cropped to selection",
                       "已裁剪到选区", "已裁剪到選取範圍"))
    }

    // MARK: 键盘

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard isActive, event.modifierFlags.contains(.command) else { return false }
        // 全局热键在会话中已注销，这里接管它，否则无法用热键结束会话
        if Prefs.hotKeySpec.matches(event) { finish(); return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "z":
            if event.modifierFlags.contains(.shift) { redo() } else { undo() }
            return true
        // 下面这些只作用于"选择"，而选择只在指针工具下可见 ——
        // 否则会对着一个看不见的选区生效，那是很容易误删的。
        case "a" where event.modifierFlags.contains(.command):
            guard tool == .select else { return false }
            selectAll(); return true
        case "g" where event.modifierFlags.contains(.command):
            guard tool == .select else { return false }
            if event.modifierFlags.contains(.shift) { ungroupSelection() } else { groupSelection() }
            return true
        case "\u{7F}", "\u{8}":      // Delete / Backspace
            guard tool == .select, activeCanvas?.selection.isEmpty == false else { return false }
            deleteSelection(); return true
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
            // 拖动中按 ESC 只取消这次拖动 —— 不能直接结束会话，那会把已有标注全丢掉
            if views.contains(where: { $0.isDragging }) {
                views.forEach { $0.cancelDrag() }
                return true
            }
            if let st = activeCanvas, st.isZoomed { views.forEach { $0.enterZoom(1, center: nil) }; applyTool(previousTool, silent: false); return true }
            finish(); return true
        case 123, 124, 125, 126: // 方向键
            // 选择工具下：微调选中对象（⇧ 加速 10 倍）
            if tool == .select, activeCanvas?.selection.isEmpty == false {
                let step: CGFloat = shift ? 10 : 1
                let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
                let dy: CGFloat = event.keyCode == 125 ? step : (event.keyCode == 126 ? -step : 0)
                nudgeSelection(dx: dx, dy: dy)
                return true
            }
            guard tool == .region, activeCanvas.map({ $0.region != nil || $0.regionPath != nil }) == true else { return false }
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
        case "v": setTool(.select); return true
        case " ":                       // 空格：临时借用指针，松开还原
            pushTemporaryTool(.select)
            return true
        case "n": setTool(.number); return true
        case "s": setTool(.spotlight); return true
        case "u": setTool(.blur); return true
        case "i": setTool(.pixelate); return true
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
        // 放大镜是 screenSaver+2 的浮动面板，层级比 NSMenu 的弹出层高得多，
        // 不收起就会盖住右键菜单。
        let magWasVisible = magnifier?.isVisible ?? false
        magnifier?.orderOut(nil)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        if magWasVisible, tool == .magnifier { magnifier?.orderFrontRegardless() }
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
        let cropItem = NSMenuItem(title: LS("Auf Auswahl zuschneiden", "Crop to selection",
                                            "裁剪到选区", "裁剪到選取範圍"),
                                  action: #selector(menuCrop), keyEquivalent: "")
        cropItem.target = self
        cropItem.isEnabled = activeCanvas.map { $0.region != nil || $0.regionPath != nil } ?? false
        m.addItem(cropItem)
        let rotL = NSMenuItem(title: LS("Um 90° nach links drehen", "Rotate 90° left",
                                        "向左旋转 90°", "向左旋轉 90°"),
                              action: #selector(menuRotateLeft), keyEquivalent: "")
        rotL.target = self
        m.addItem(rotL)
        let rotR = NSMenuItem(title: LS("Um 90° nach rechts drehen", "Rotate 90° right",
                                        "向右旋转 90°", "向右旋轉 90°"),
                              action: #selector(menuRotateRight), keyEquivalent: "")
        rotR.target = self
        m.addItem(rotR)
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
    @objc private func menuCrop() { cropToRegion() }
    @objc private func menuRotateLeft() { rotateCanvas(clockwise: false) }
    @objc private func menuRotateRight() { rotateCanvas(clockwise: true) }
    @objc private func menuCopy() { Exporter.copyToClipboard(activeCanvas) }
    @objc private func menuSave() { Exporter.saveWithPanel(activeCanvas, screen: activeCanvas?.screen) }
    @objc private func menuPrint() { Exporter.print(activeCanvas) }
    @objc private func menuMail() { Exporter.composeMail(activeCanvas, openFolderFirst: true) }
    @objc private func menuFinish() { finish() }
}

// MARK: - 浅色按钮

/// 自绘按钮：深色面板上需要浅色底 + 深色字才看得清。
/// AppKit 的圆角按钮在这个深蓝面板上会渲染成暗底黑字，对比度极低。
final class LightButton: NSButton {
    var fill = NSColor(srgbRed: 0.94, green: 0.96, blue: 1.0, alpha: 1)
    var textColor = NSColor(srgbRed: 0.09, green: 0.15, blue: 0.30, alpha: 1)

    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseDown(with event: NSEvent) {
        pressing = true
        super.mouseDown(with: event)     // 让 NSButton 照常处理点击与高亮
        pressing = false
    }

    override func draw(_ dirtyRect: NSRect) {
        var bg = fill
        if pressing { bg = fill.blended(withFraction: 0.16, of: .black) ?? fill }
        else if hovering { bg = fill.blended(withFraction: 0.06, of: .black) ?? fill }

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 7, yRadius: 7)
        bg.setFill()
        path.fill()
        NSColor(srgbRed: 0.55, green: 0.62, blue: 0.80, alpha: 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: textColor
        ]
        let str = title as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2),
                 withAttributes: attrs)
    }
}

// MARK: - 界面布局配置的保存 / 载入 / 重置

/// 自检用：只重置偏好，不触碰 UI
func LayoutConfigResetForTest() { Prefs.resetLayout() }

enum LayoutConfig {

    static func save() {
        let panel = NSSavePanel()
        panel.title = LS("Layout speichern", "Save layout", "保存布局", "儲存版面")
        panel.nameFieldStringValue = "PentoPic-Layout.json"
        panel.allowedContentTypes = [.json]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)
        let resp = SessionController.shared.withSuspendedOverlays { panel.runModal() }
        guard resp == .OK, let url = panel.url else { return }
        let payload: [String: Any] = ["version": 1,
                                      "app": Brand.name,
                                      "layout": Prefs.layoutSnapshot]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            SessionController.shared.flashStatus(LS("Layout gespeichert", "Layout saved", "布局已保存", "版面已儲存"))
        } catch {
            Alert.error(LS("Speichern fehlgeschlagen", "Save failed", "保存失败", "儲存失敗"), error.localizedDescription)
        }
    }

    static func load() {
        let panel = NSOpenPanel()
        panel.title = LS("Layout laden", "Load layout", "载入布局", "載入版面")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)
        let resp = SessionController.shared.withSuspendedOverlays { panel.runModal() }
        guard resp == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let layout = obj["layout"] as? [String: Any] else {
                Alert.error(LS("Ungültige Datei", "Invalid file", "文件无效", "檔案無效"),
                            LS("Diese Datei enthält kein Layout.", "This file contains no layout.", "该文件里没有布局配置。", "該檔案裡沒有版面設定。"))
                return
            }
            Prefs.applyLayout(layout)
            SessionController.shared.onToolChanged()
            SessionController.shared.rebuildToolbar()
            SessionController.shared.flashStatus(LS("Layout geladen", "Layout loaded", "布局已载入", "版面已載入"))
        } catch {
            Alert.error(LS("Laden fehlgeschlagen", "Load failed", "载入失败", "載入失敗"), error.localizedDescription)
        }
    }

    static func reset() {
        Prefs.resetLayout()
        SessionController.shared.setSwatch(0)
        SessionController.shared.setPenSize(1)
        SessionController.shared.applyToolPublic(.pen)
        SessionController.shared.onToolChanged()
        SessionController.shared.rebuildToolbar()
        SessionController.shared.flashStatus(LS("Standardlayout wiederhergestellt",
                                                "Default layout restored",
                                                "已恢复默认布局",
                                                "已恢復預設版面"))
    }
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

        let btn = LightButton(frame: NSRect(x: 10, y: 8, width: 130, height: 28))
        let delay = Prefs.captureDelay
        btn.title = delay > 0
            ? LS("Start (\(delay) s)", "Start (\(delay) s)", "开始 (\(delay) 秒)", "開始 (\(delay) 秒)")
            : LS("Start", "Start", "开始", "開始")
        btn.target = self
        btn.action = #selector(clicked)
        btn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
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
