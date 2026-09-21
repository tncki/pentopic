// PreviewMain.swift — 离屏渲染自检：工具栏外观 + 全部图形 + 合成方向验证
import AppKit
import SwiftUI
import Carbon.HIToolbox

// 项目根目录从本文件位置推导（Tools/preview/main.swift → 上溯三层），
// 避免硬编码绝对路径 —— 这样改目录名、别人 clone 后都能直接用
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tools/preview
    .deletingLastPathComponent()   // Tools
    .deletingLastPathComponent()   // 项目根
let outDir = projectRoot.appendingPathComponent("preview")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
Prefs.registerDefaults()
// 可用 POFIX_LANG=en|zh-Hans|zh-Hant|de 指定语言，默认英文
if let raw = ProcessInfo.processInfo.environment["POFIX_LANG"], let l = AppLang(rawValue: raw) {
    L.lang = l
} else {
    L.lang = .en
}
print("语言: \(L.lang.rawValue)")
// 后面的诊断会调用 SettingsModel.save()，而它会执行 L.lang = Prefs.resolveLanguage()
// （应用里的正常行为），从而覆盖这里的设置。先存下来，诊断结束后还原，
// 否则后续所有渲染都会用被覆盖的语言。
let intendedLang = L.lang

// 四语对照抽样（验证繁体译文与简体结构一致、没有错位）
let samples: [(String, String, String, String)] = [
    ("Freehand pen", "自由画笔", "自由筆刷", "Freihand-Stift"),
    ("Settings", "信息与设置", "資訊與設定", "Info und Einstellungen"),
    ("Screen Recording", "屏幕录制", "螢幕錄製", "Bildschirmaufnahme"),
    ("Save as", "另存为", "另存新檔", "Speichern unter"),
    ("Print", "打印", "列印", "Drucken"),
    ("Clipboard", "剪贴板", "剪貼簿", "Zwischenablage"),
]
print("\n四语抽样:")
for (en, zh, hant, de) in samples {
    print("  en=\(en) | zh=\(zh) | hant=\(hant) | de=\(de)")
}
print("")

func renderView(_ v: NSView, named name: String) {
    let w = NSWindow(contentRect: v.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    w.contentView = v
    v.layoutSubtreeIfNeeded()
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("no rep"); return }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { print("no png"); return }
    let url = outDir.appendingPathComponent(name)
    try? data.write(to: url)
    print("wrote \(url.path)  \(Int(v.bounds.width))x\(Int(v.bounds.height))")
}

// ---------------------------------------------------------------- 1. 工具栏
let model = ToolbarModel()
model.isActive = true
model.tool = .pen
model.swatchIndex = 0
model.penSizeIndex = 1
model.swatches = Palette.all
model.canUndo = true
model.hasStrokes = true
let toolbar = ToolbarView(model: model, controller: SessionController.shared)
let hosting = NSHostingView(rootView: toolbar)
let fit = hosting.fittingSize
hosting.frame = NSRect(x: 0, y: 0, width: fit.width, height: fit.height)
renderView(hosting, named: "01-toolbar-\(L.lang.rawValue).png")

// 选择工具下的排列面板（只在选择工具激活时出现）
do {
    model.tool = .select
    model.selectedCount = 3
    let sel = ToolbarView(model: model, controller: SessionController.shared)
    let h2 = NSHostingView(rootView: sel)
    let f2 = h2.fittingSize
    h2.frame = NSRect(x: 0, y: 0, width: f2.width, height: f2.height)
    renderView(h2, named: "12-toolbar-select-\(L.lang.rawValue).png")
    model.tool = .pen
    model.selectedCount = 0
}

// ---------------------------------------------------------------- 1b. 设置窗口（文字最密集，用来验证四语）
do {
    let sm = SettingsModel()
    sm.load()
    let sv = SettingsView(m: sm, onClose: {})
    let h = NSHostingView(rootView: sv)
    let f = h.fittingSize
    h.frame = NSRect(x: 0, y: 0, width: f.width, height: f.height)
    renderView(h, named: "00-settings-\(L.lang.rawValue).png")
}

// ---------------------------------------------------------------- 1c. 诊断：设置视图与颜色面板
do {
    print("\n[诊断] 创建 SettingsView 之前 NSColorPanel.isVisible = \(NSColorPanel.shared.isVisible)")
    let sm2 = SettingsModel()
    sm2.load()
    let sv2 = SettingsView(m: sm2, onClose: {})
    let h2 = NSHostingView(rootView: sv2)
    let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w2.contentView = h2
    h2.layoutSubtreeIfNeeded()
    print("[诊断] 创建并放入窗口之后 NSColorPanel.isVisible = \(NSColorPanel.shared.isVisible)")
    print("[诊断] 窗口里是否有 NSColorWell 子视图 = \(h2.subviews.count) 个直接子视图")

    // 额外颜色：模型 → Prefs → Palette 链路
    sm2.extraColors = ["#FF7A00", "#00C2A8"]
    sm2.save()
    print("[验证] 附加颜色保存后 Prefs.extraColors = \(Prefs.extraColors)")
    print("[验证] Palette.all.count = \(Palette.all.count)  (标准 10 + 附加 \(Palette.extra.count))")

    // 文件夹路径：save() 是否真的写回
    let tmpA = NSTemporaryDirectory() + "pofix-A", tmpB = NSTemporaryDirectory() + "pofix-B"
    sm2.screenshotFolder = tmpA
    sm2.emailFolder = tmpB
    sm2.save()
    print("[验证] 截图目录写回 = \(Prefs.screenshotFolder.path == tmpA ? "OK" : "失败(\(Prefs.screenshotFolder.path))")")
    print("[验证] 邮件目录写回 = \(Prefs.emailFolder.path == tmpB ? "OK" : "失败(\(Prefs.emailFolder.path))")")
    print("[验证] 目录已自动创建 = \(FileManager.default.fileExists(atPath: tmpA) ? "OK" : "失败")")

    // 本地化声明：NSOpenPanel / NSSavePanel 等系统面板按"宿主应用的本地化"渲染，
    // preferredLocalizations 就是系统面板实际会用的语言。
    print("[验证] Bundle.localizations          = \(Bundle.main.localizations.sorted())")
    print("[验证] Bundle.preferredLocalizations = \(Bundle.main.preferredLocalizations)")
    print("[验证] 系统语言                       = \(Locale.preferredLanguages.prefix(2))")

    // 版权声明
    print("[验证] Brand.version   = \(Brand.version)")
    print("[验证] Brand.copyright = \(Brand.copyright)")

    // 单独渲染「关于」区块
    let aboutHost = NSHostingView(rootView: sv2.about)
    aboutHost.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
    renderView(aboutHost, named: "02-about-\(L.lang.rawValue).png")

    Prefs.extraColors = []
    Prefs.setScreenshotFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pointofix/Screenshots"))
    Prefs.language = nil                 // 别把诊断用的目录/语言写进持久化设置
    L.lang = intendedLang                // 还原 save() 覆盖掉的全局语言
    print("")
}

// ---------------------------------------------------------------- 1d. 验证模态 run loop 里的轮询定时器
// 授权引导靠"弹窗打开期间轮询权限、拿到就自动关闭"来免掉手动点「重试」，
// 前提是定时器能在 NSAlert.runModal() 的模态 run loop 中触发。这里实测一次。
do {
    let a = NSAlert()
    a.messageText = "modal timer self-test"
    a.informativeText = "此弹窗会在 0.6 秒后自动关闭"
    a.addButton(withTitle: "OK")
    var fired = false
    let timer = Timer(timeInterval: 0.6, repeats: false) { t in
        fired = true
        t.invalidate()
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
        a.window.orderOut(nil)
    }
    RunLoop.current.add(timer, forMode: .modalPanel)
    // 保险：万一模态定时器不触发，3 秒后强制退出，避免卡死
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        if !fired { NSApp.stopModal(withCode: .alertSecondButtonReturn); a.window.orderOut(nil) }
    }
    let t0 = Date()
    _ = a.runModal()
    let dt = Date().timeIntervalSince(t0)
    print("[验证] 模态 run loop 中定时器触发 = \(fired ? "OK" : "失败")  (耗时 \(String(format: "%.2f", dt))s)")
    print("")
}

// ---------------------------------------------------------------- 1e. 设置窗口反复开关（闪退回归测试）
// 之前的 bug：closeWindow() 里 window.close() 会同步发出 willCloseNotification，
// 观察者又调用 closeWindow()，而 window 是在 close() 之后才置空 —— 无限递归导致闪退。
// 这里真的把设置窗口开关若干次，如果有递归会直接崩掉这个进程。
do {
    for i in 1...5 {
        SettingsWindowController.shared.show()
        let windows = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.isVisible }
        guard let w = windows.first else { print("[验证] 第 \(i) 次：设置窗口未出现 ❌"); break }
        w.close()                       // 等价于点「取消」/「确定」/红叉
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if i == 1 { print("[验证] 设置窗口关闭路径无递归闪退 = OK（开关 5 次）") }
    }
    print("")
}

// ---------------------------------------------------------------- 1f. 快捷键规格单元测试
do {
    print("[验证] 全局热键规格")
    var pass = 0, fail = 0
    func expect(_ name: String, _ got: String, _ want: String) {
        if got == want { pass += 1; print("  PASS  \(name) = \(got)") }
        else { fail += 1; print("  FAIL  \(name) = \(got)，期望 \(want)") }
    }
    func expectBool(_ name: String, _ got: Bool, _ want: Bool) {
        expect(name, got ? "true" : "false", want ? "true" : "false")
    }

    let f9 = HotKeySpec(keyCode: UInt32(kVK_F9), modifiers: 0)
    let cmdP = HotKeySpec(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey))
    let cmdShiftP = HotKeySpec(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey))
    let bareP = HotKeySpec(keyCode: UInt32(kVK_ANSI_P), modifiers: 0)

    expect("F9 显示", f9.display, "F9")
    expect("⌘P 显示", cmdP.display, "⌘P")
    expect("⌘⇧P 显示（macOS 惯例顺序 ⌃⌥⇧⌘）", cmdShiftP.display, "⇧⌘P")

    expectBool("F9 合法（功能键无需修饰键）", f9.isValid, true)
    expectBool("⌘P 合法", cmdP.isValid, true)
    expectBool("裸 P 非法（会全局劫持字母键）", bareP.isValid, false)

    expectBool("⌘P 有冲突警告", cmdP.conflictWarning != nil, true)
    expectBool("F9 无冲突警告", f9.conflictWarning == nil, true)
    expectBool("⌘⇧P 无冲突警告（非系统保留）", cmdShiftP.conflictWarning == nil, true)

    print("  快捷键规格: \(pass) 通过, \(fail) 失败")
    print("")
}

// ---------------------------------------------------------------- 1g. 启动按钮面板
do {
    let panel = StartButtonPanel { }
    if let cv = panel.contentView {
        cv.layoutSubtreeIfNeeded()
        renderView(cv, named: "03-startbutton-\(L.lang.rawValue).png")
    }
}

// ---------------------------------------------------------------- 1h. 序号居中放大检查
do {
    if let scr = (NSScreen.main ?? NSScreen.screens.first),
       let st = CanvasState(screen: scr, captured: nil) {
        st.background = BackgroundKind.white
        // 大中小三种直径各画一个，方便肉眼判断居中
        for (i, d) in [CGFloat(60), 100, 160].enumerated() {
            let c = CGPoint(x: 160 + CGFloat(i) * 220, y: 160)
            let stk = Stroke(shape: .number(i + 1, c, d, .circle), color: Palette.red, width: 6)
            st.layer.apply(stk); st.strokes.append(stk)
        }
        if let cg = st.composeCG(crop: CGRect(x: 40, y: 40, width: 640, height: 240)) {
            let url = outDir.appendingPathComponent("11-number-centering.png")
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)  \(cg.width)x\(cg.height)")
        }
    }
}

// ---------------------------------------------------------------- 2. 全部工具
guard let screen = NSScreen.main ?? NSScreen.screens.first else {
    print("no screen"); exit(1)
}

/// 合成一张假的“屏幕截图”（左上角标记 TOP-LEFT 用于验证方向）
func makeFakeScreen(pointSize: CGSize, scale: CGFloat) -> CGImage? {
    let pw = Int(pointSize.width * scale), ph = Int(pointSize.height * scale)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: pointSize.height)
    ctx.scaleBy(x: 1, y: -1)
    // 模拟桌面：白底 + 顶部标题栏 + 几块色块
    ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).cgColor)
    ctx.fill(CGRect(origin: .zero, size: pointSize))
    ctx.setFillColor(NSColor(srgbRed: 0.20, green: 0.30, blue: 0.55, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pointSize.width, height: 34))
    ctx.setFillColor(NSColor(srgbRed: 0.35, green: 0.62, blue: 0.85, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 40, y: 90, width: 320, height: 180))
    ctx.setFillColor(NSColor(srgbRed: 0.90, green: 0.75, blue: 0.35, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 400, y: 120, width: 220, height: 120))
    // 方向标记
    ShapeRenderer.drawText(ctx, "TOP-LEFT", origin: CGPoint(x: 24, y: 46), fontSize: 30, color: .black)
    ShapeRenderer.drawText(ctx, "TOP BAR", origin: CGPoint(x: 12, y: 6), fontSize: 22, color: .white)
    return ctx.makeImage()
}

let fake = makeFakeScreen(pointSize: screen.frame.size, scale: screen.backingScaleFactor)
let cap = fake.map { CapturedScreen(displayID: 0, cgImage: $0,
                                    pointSize: screen.frame.size,
                                    scale: screen.backingScaleFactor) }

// 2a. 白纸 + 全部图形
if let st = CanvasState(screen: screen, captured: cap) {
    st.background = .white
    let w = st.pointSize.width
    var strokes: [Stroke] = []
    let red = Palette.red, yellow = Palette.yellow, green = Palette.green, blue = Palette.blue
    let marker = NSColor(srgbRed: 0.95, green: 0.85, blue: 0.1, alpha: Palette.markerAlpha)

    strokes.append(Stroke(shape: .freehand((0..<60).map { i in
        CGPoint(x: 60 + CGFloat(i) * 4, y: 120 + sin(CGFloat(i) / 5) * 30) }), color: red, width: 5))
    strokes.append(Stroke(shape: .line(CGPoint(x: 340, y: 90), CGPoint(x: 460, y: 150)), color: blue, width: 4))
    strokes.append(Stroke(shape: .arrow(CGPoint(x: 500, y: 150), CGPoint(x: 640, y: 90)), color: red, width: 5))
    strokes.append(Stroke(shape: .doubleArrow(CGPoint(x: 700, y: 90), CGPoint(x: 860, y: 150)), color: NSColor.black, width: 4))
    strokes.append(Stroke(shape: .rect(CGRect(x: 60, y: 210, width: 160, height: 90)), color: blue, width: 4))
    strokes.append(Stroke(shape: .rectFilled(CGRect(x: 260, y: 210, width: 160, height: 90)), color: NSColor(srgbRed: 0.4, green: 0.75, blue: 0.45, alpha: Palette.markerAlpha), width: 2))
    strokes.append(Stroke(shape: .ellipse(CGRect(x: 460, y: 210, width: 170, height: 90)), color: red, width: 4))
    strokes.append(Stroke(shape: .ellipseFilled(CGRect(x: 670, y: 210, width: 170, height: 90)), color: NSColor(srgbRed: 0.95, green: 0.4, blue: 0.4, alpha: Palette.markerAlpha), width: 2))
    strokes.append(Stroke(shape: .text("Text-Werkzeug\n第二行 mehrzeilig", CGPoint(x: 60, y: 330), 26), color: blue, width: 4))
    strokes.append(Stroke(shape: .check(CGPoint(x: 480, y: 360), 56), color: green, width: 4))
    strokes.append(Stroke(shape: .cross(CGPoint(x: 600, y: 360), 56), color: red, width: 4))
    strokes.append(Stroke(shape: .freehand((0..<40).map { i in
        CGPoint(x: 700 + CGFloat(i) * 5, y: 345 + sin(CGFloat(i) / 3) * 12) }), color: marker, width: 26))
    strokes.append(Stroke(shape: .number(1, CGPoint(x: 120, y: 470), 44, .circle), color: red, width: 4))
    strokes.append(Stroke(shape: .number(2, CGPoint(x: 200, y: 470), 44, .circle), color: blue, width: 4))
    strokes.append(Stroke(shape: .number(3, CGPoint(x: 280, y: 470), 44, .circle), color: NSColor.black, width: 4))
    strokes.append(Stroke(shape: .spotlight(CGRect(x: 420, y: 400, width: 360, height: 180)), color: red, width: 4))
    for s in strokes { st.layer.apply(s); st.strokes.append(s) }
    if let cg = st.composeCG() {
        let url = outDir.appendingPathComponent("02-tools.png")
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)  \(cg.width)x\(cg.height)")
    }
}

// 2b. 方向验证：把标注画在已知位置，确认导出图方向正确
if let st = CanvasState(screen: screen, captured: cap) {
    st.background = .currentScreen
    let s1 = Stroke(shape: .text("A1 标注在左上", CGPoint(x: 200, y: 200), 40), color: Palette.red, width: 6)
    let s2 = Stroke(shape: .rect(CGRect(x: 190, y: 190, width: 420, height: 80)), color: Palette.blue, width: 4)
    let s3 = Stroke(shape: .arrow(CGPoint(x: 900, y: 400), CGPoint(x: 620, y: 240)), color: Palette.red, width: 8)
    for s in [s1, s2, s3] { st.layer.apply(s); st.strokes.append(s) }
    if let cg = st.composeCG() {
        let url = outDir.appendingPathComponent("03-compose.png")
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)  \(cg.width)x\(cg.height)")
    }
}

// 2c. 方格纸背景
if let st = CanvasState(screen: screen, captured: cap) {
    st.background = .grid
    let s = Stroke(shape: .rect(CGRect(x: 150, y: 150, width: 300, height: 200)), color: Palette.red, width: 6)
    st.layer.apply(s); st.strokes.append(s)
    if let cg = st.composeCG(crop: CGRect(x: 100, y: 100, width: 600, height: 400)) {
        let url = outDir.appendingPathComponent("04-grid-region.png")
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)  \(cg.width)x\(cg.height) (选区裁剪)")
    }
}

// 2d. 橡皮擦验证：画笔 + 橡皮擦部分擦除
if let st = CanvasState(screen: screen, captured: cap) {
    st.background = .white
    let pen1 = Stroke(shape: .freehand((0..<80).map { i in
        CGPoint(x: 80 + CGFloat(i) * 9, y: 200) }), color: Palette.red, width: 14)
    let pen2 = Stroke(shape: .freehand((0..<80).map { i in
        CGPoint(x: 80 + CGFloat(i) * 9, y: 260) }), color: Palette.blue, width: 14)
    let marker = Stroke(shape: .rectFilled(CGRect(x: 80, y: 320, width: 720, height: 60)),
                        color: NSColor(srgbRed: 0.95, green: 0.85, blue: 0.1, alpha: Palette.markerAlpha), width: 2)
    for s in [pen1, pen2, marker] { st.layer.apply(s); st.strokes.append(s) }
    // 橡皮擦横穿所有内容
    let er = Stroke(shape: .freehand((0..<60).map { i in
        CGPoint(x: 420 + CGFloat(i) * 2, y: 150 + CGFloat(i) * 4) }), color: .black, width: 40, isEraser: true)
    st.layer.apply(er); st.strokes.append(er)
    if let cg = st.composeCG(crop: CGRect(x: 60, y: 120, width: 800, height: 320)) {
        let url = outDir.appendingPathComponent("05-eraser.png")
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path) (橡皮擦：斜带应露出白底并切断三条线)")
    }
}

// 2e. 撤销 / 重放一致性：rebuild 后应与逐条 apply 结果一致
if let st = CanvasState(screen: screen, captured: cap) {
    st.background = .white
    let a = Stroke(shape: .rect(CGRect(x: 100, y: 100, width: 300, height: 200)), color: Palette.red, width: 8)
    let b = Stroke(shape: .ellipseFilled(CGRect(x: 200, y: 150, width: 400, height: 200)),
                   color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: Palette.markerAlpha), width: 3)
    let c = Stroke(shape: .freehand((0..<30).map { i in CGPoint(x: 120 + CGFloat(i)*12, y: 400) }), color: .black, width: 10)
    let d = Stroke(shape: .freehand((0..<25).map { i in CGPoint(x: 200 + CGFloat(i)*14, y: 380 + CGFloat(i)) }),
                   color: .black, width: 34, isEraser: true)
    let e = Stroke(shape: .text("rebuild OK", CGPoint(x: 420, y: 300), 34), color: Palette.green, width: 4)
    st.strokes = [a, b, c, d, e]
    st.rebuild()     // 模拟撤销后的重放
    if let cg = st.composeCG(crop: CGRect(x: 60, y: 60, width: 700, height: 420)) {
        let url = outDir.appendingPathComponent("06-rebuild.png")
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path) (撤销重放)")
    }
}

// ---------------------------------------------------------------- 3. 会话生命周期
func renderInPlace(_ v: NSView, named: String) {
    v.layoutSubtreeIfNeeded()
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let d = rep.representation(using: .png, properties: [:]) else { return }
    let url = outDir.appendingPathComponent(named)
    try? d.write(to: url)
    print("wrote \(url.path)  \(Int(v.bounds.width))x\(Int(v.bounds.height))")
}

setenv("POFIX_FAKE_CAPTURE", "1", 1)
let sc = SessionController.shared
sc.start()
RunLoop.current.run(until: Date().addingTimeInterval(1.6))
print("session active=\(sc.isActive) canvases=\(sc.canvases.count) views=\(sc.allViews().count)")

if let v = sc.allViews().first {
    renderInPlace(v, named: "07-overlay-session.png")
    // 覆盖层上画几笔，验证真实视图绘制路径
    // 打码必须放在**有细节的区域**（文字、色块），放在纯色区看不出任何变化。
    // 把打码放在有文字的行上 —— 纯色区域上打码看不出变化
    let blurStroke = Stroke(shape: .redact(CGRect(x: 414, y: 158, width: 330, height: 62), .blur),
                            color: .black, width: 4)
    let pixelStroke = Stroke(shape: .redact(CGRect(x: 414, y: 114, width: 330, height: 40), .pixelate),
                             color: .black, width: 4)
    let s1 = Stroke(shape: .arrow(CGPoint(x: 860, y: 330), CGPoint(x: 760, y: 200)), color: Palette.red, width: 9)
    let s2 = Stroke(shape: .text("Live-Overlay", CGPoint(x: 60, y: 480), 46), color: Palette.blue, width: 6)
    let s3 = Stroke(shape: .check(CGPoint(x: 300, y: 560), 90), color: Palette.green, width: 6)
    let s4 = Stroke(shape: .number(1, CGPoint(x: 640, y: 430), 46, .circle), color: Palette.red, width: 5)
    let s5 = Stroke(shape: .number(2, CGPoint(x: 720, y: 430), 46, .circle), color: Palette.red, width: 5)
    for s in [blurStroke, pixelStroke, s1, s2, s3, s4, s5] {
        v.state.layer.apply(s); v.state.strokes.append(s)
    }
    v.needsDisplay = true
    v.displayIfNeeded()
    renderInPlace(v, named: "08-overlay-annotated.png")

    // 聚焦高亮单独一张：它会把其余部分压暗，和别的标注混在一起看不清
    v.state.strokes.removeAll()
    v.state.layer.clear()
    let spot = Stroke(shape: .spotlight(CGRect(x: 620, y: 200, width: 520, height: 300)),
                      color: Palette.red, width: 5)
    v.state.layer.apply(spot); v.state.strokes.append(spot)
    v.needsDisplay = true
    v.displayIfNeeded()
    renderInPlace(v, named: "10-spotlight.png")
}

for w in NSApp.windows where w.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1 {
    if let cv = w.contentView { renderInPlace(cv, named: "09-toolbar-live.png") }
}

// 键盘快捷键路径
func fakeKey(_ chars: String, code: UInt16, mods: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
                     windowNumber: 0, context: nil, characters: chars,
                     charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}
print("tool after 'p' = \(sc.handleKeyDown(fakeKey("p", code: 35)) ? sc.tool.rawValue : "n/a")")
print("tool after 'f' = \(sc.handleKeyDown(fakeKey("f", code: 3)) ? sc.tool.rawValue : "n/a")")
print("pen size after '3' = ", terminator: "")
_ = sc.handleKeyDown(fakeKey("3", code: 20)); print(sc.penSize)
print("undo ok = \(sc.handleKeyEquivalent(fakeKey("z", code: 6, mods: .command)))")
sc.finish()
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
print("after finish active=\(sc.isActive) views=\(sc.allViews().count)")

// ---------------------------------------------------------------- 4. 取色器单元自检
// 构造已知像素的位图，逐点验证 PixelSampler 的行列对应关系（改过实现，必须锁死）
do {
    let W = 64, H = 48
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 用与应用一致的约定建图：左上角原点、y 轴向下、行 0 = 顶部
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    func setPx(_ x: Int, _ y: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        ctx.setFillColor(NSColor(srgbRed: r, green: g, blue: b, alpha: 1).cgColor)
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    setPx(10, 20, 1, 0, 0)        // 红
    setPx(0, 0, 0, 1, 0)          // 左上角绿
    setPx(W - 1, H - 1, 0, 0, 1)  // 右下角蓝
    setPx(63, 0, 1, 1, 1)         // 右上角白
    let img = ctx.makeImage()!

    var ok = 0, bad = 0
    func expect(_ x: Int, _ y: Int, _ want: String) {
        let got = PixelSampler.color(of: img, at: CGPoint(x: x, y: y))?.hexString ?? "nil"
        if got == want { ok += 1; print("  PASS  取色 (\(x),\(y)) = \(got)") }
        else { bad += 1; print("  FAIL  取色 (\(x),\(y)) = \(got)，期望 \(want)") }
    }
    print("[取色器] （CGImage 行 0 = 顶部，y 向下）")
    expect(10, 20, "#FF0000")
    expect(0, 0, "#00FF00")
    expect(63, 47, "#0000FF")
    expect(63, 0, "#FFFFFF")
    let outOfRange = PixelSampler.color(of: img, at: CGPoint(x: 999, y: 999))
    if outOfRange == nil { ok += 1; print("  PASS  越界返回 nil") }
    else { bad += 1; print("  FAIL  越界未返回 nil") }
    print("  取色器: \(ok) 通过, \(bad) 失败")
}

print("done")
exit(0)
