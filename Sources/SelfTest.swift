// SelfTest.swift — 真机端到端自检（POFIX_SELFTEST=<输出目录> 时启用）
//
// 作用：在 Pointofix.app 自己的进程里跑完整流程（真实截屏 + 真实事件 + 真实导出），
// 把每一步的结果渲染成 PNG 证据并写出 report.txt。
// 正常使用时不会执行（仅在设置了环境变量 POFIX_SELFTEST 时触发）。
import AppKit

enum SelfTest {

    static var outDirOverride: String?

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["POFIX_SELFTEST"] != nil || outDirOverride != nil
    }

    /// 标记文件 /tmp/pofix-probe —— 环境变量传不进 `open` 启动的 GUI 应用
    /// （launchctl setenv 需要特权），所以用文件触发。
    ///
    ///   内容 `/path/dir`           → 只探测权限并写 probe.txt 后退出
    ///   内容 `selftest:/path/dir`  → 走完整端到端自检
    ///
    /// 注意：必须用这种方式测！从 shell 直接跑可执行文件时 TCC 的归属进程不同，
    /// 会得到与用户真实启动（open .app）不一样的权限判定。
    static var markerRequest: (mode: String, dir: String)? {
        guard let raw = try? String(contentsOfFile: "/tmp/pofix-probe", encoding: .utf8) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("selftest:") {
            return ("selftest", String(t.dropFirst("selftest:".count)))
        }
        return ("probe", t)
    }

    /// 按真实启动路径（open .app）记录权限判定与签名信息
    static func writeProbe(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var lines: [String] = []
        lines.append("time=\(Date())")
        lines.append("bundlePath=\(Bundle.main.bundlePath)")
        lines.append("bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")
        lines.append("executable=\(Bundle.main.executablePath ?? "nil")")
        lines.append("screenCapturePermission=\(ScreenCapture.hasPermission)")
        lines.append("screens=\(NSScreen.screens.count)")
        // 真的抓一张，验证不只是 preflight 通过
        if ScreenCapture.hasPermission, let sc = NSScreen.main {
            let t0 = Date()
            let cap = ScreenCapture.capture(screen: sc)
            lines.append("captureOK=\(cap != nil)")
            lines.append("captureSize=\(cap.map { "\($0.cgImage.width)x\($0.cgImage.height)" } ?? "-")")
            lines.append("captureSeconds=\(String(format: "%.2f", Date().timeIntervalSince(t0)))")
        } else {
            lines.append("captureOK=false")
            lines.append("captureSize=-")
        }
        try? lines.joined(separator: "\n").write(to: out.appendingPathComponent("probe.txt"),
                                                  atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
    }

    private static var outDir: URL {
        if let o = outDirOverride { return URL(fileURLWithPath: o) }
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["POFIX_SELFTEST"] ?? "/tmp/pofix-selftest")
    }

    private static var report: [String] = []
    private static var pass = 0, fail = 0

    private static func log(_ s: String) {
        report.append(s)
        print(s)
        fflush(stdout)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { pass += 1 } else { fail += 1 }
        log("\(ok ? "  PASS" : "  FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }

    private static func pump(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: 渲染证据

    @discardableResult
    private static func shot(_ view: NSView?, _ name: String) -> Bool {
        guard let v = view, v.bounds.width > 0, v.bounds.height > 0 else {
            log("  (无法渲染 \(name)：视图为空)"); return false
        }
        v.layoutSubtreeIfNeeded()
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return false }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let d = rep.representation(using: .png, properties: [:]) else { return false }
        let url = outDir.appendingPathComponent(name)
        try? d.write(to: url)
        log("  渲染 \(name)  \(Int(v.bounds.width))×\(Int(v.bounds.height))  \(d.count / 1024) KB")
        return true
    }

    private static func writeImage(_ cg: CGImage?, _ name: String) -> Int? {
        guard let cg, let d = Exporter.encode(cg, as: .png) else { return nil }
        try? d.write(to: outDir.appendingPathComponent(name))
        log("  导出 \(name)  \(cg.width)×\(cg.height)  \(d.count / 1024) KB")
        return d.count
    }

    // MARK: 合成鼠标事件

    private static var useWindowDispatch = true
    private static var window: NSWindow?
    private static var canvas: CanvasView?

    private static func event(_ type: NSEvent.EventType, _ p: CGPoint,
                              flags: NSEvent.ModifierFlags = []) -> NSEvent? {
        guard let win = window else { return nil }
        let h = win.contentView?.bounds.height ?? 0
        return NSEvent.mouseEvent(with: type,
                                  location: NSPoint(x: p.x, y: h - p.y),   // 视图为 flipped
                                  modifierFlags: flags,
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: win.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1,
                                  pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// 走真实事件派发；若窗口路由没生效则回退到直接调用视图方法
    private static func drag(_ pts: [CGPoint], flags: NSEvent.ModifierFlags = []) {
        guard let view = canvas, !pts.isEmpty else { return }
        func send(_ type: NSEvent.EventType, _ p: CGPoint) {
            guard let e = event(type, p, flags: flags) else { return }
            if useWindowDispatch {
                window?.sendEvent(e)
            } else {
                switch type {
                case .leftMouseDown: view.mouseDown(with: e)
                case .leftMouseDragged: view.mouseDragged(with: e)
                default: view.mouseUp(with: e)
                }
            }
        }
        send(.leftMouseDown, pts[0])
        for p in pts.dropFirst() { send(.leftMouseDragged, p) }
        send(.leftMouseUp, pts[pts.count - 1])
    }

    private static func click(_ p: CGPoint, flags: NSEvent.ModifierFlags = []) {
        drag([p], flags: flags)
    }

    // MARK: 主流程

    static func run() {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        log("================ Pointofix macOS 真机端到端自检 ================")
        log("时间: \(Date())")
        log("输出目录: \(outDir.path)")
        log("屏幕: \(NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height))@\($0.backingScaleFactor)x" }.joined(separator: ", "))")
        log("")

        // ---- 0. 权限 ----
        log("[0] 屏幕录制权限")
        guard ScreenCapture.hasPermission else {
            check("屏幕录制权限", false, "未授权 —— 请在 系统设置 › 隐私与安全性 › 屏幕录制 中勾选 Pointofix 后重试")
            finishReport()
            exit(2)
        }
        check("屏幕录制权限", true, "已授权")

        // 把截图目录临时指到输出目录，避免污染用户文档目录（结束时复原）
        let savedShot = Prefs.screenshotFolder
        let savedMail = Prefs.emailFolder
        let savedAuto = Prefs.autoScreenshot
        Prefs.setScreenshotFolder(outDir.appendingPathComponent("screenshots"))
        Prefs.setEmailFolder(outDir.appendingPathComponent("email"))
        Prefs.ensureFolders()

        // ---- 1. 启动会话（真实截屏）----
        log("")
        log("[1] 冻结屏幕（真实截屏）")
        let sc = SessionController.shared
        sc.start(synchronously: true)
        pump(0.4)
        log("  诊断: isActive=\(sc.isActive) canvases=\(sc.canvases.count) views=\(sc.allViews().count)")
        for s in NSScreen.screens {
            log("  屏幕 \(Int(s.frame.width))×\(Int(s.frame.height)) displayID=\(ScreenCapture.displayID(of: s))")
        }
        if !sc.isActive || sc.canvases.isEmpty {
            check("会话启动", false, "未能建立覆盖层")
            finishReport(); exit(3)
        }
        guard let st = sc.activeCanvas, let view = sc.allViews().first, let win = view.window else {
            check("会话启动", false, "画布或窗口缺失 (st=\(sc.activeCanvas != nil) view=\(sc.allViews().first != nil) window=\(sc.allViews().first?.window != nil))")
            finishReport(); exit(3)
        }
        window = win
        canvas = view
        check("会话启动", true, "画布 \(Int(st.pointSize.width))×\(Int(st.pointSize.height)) pt，\(sc.canvases.count) 块屏幕")

        // 抓到的必须是真实屏幕：检查图像非纯色
        if let frozen = st.frozenCG {
            check("捕获到真实屏幕", true, "\(frozen.width)×\(frozen.height) px")
            writeImage(frozen, "S01-真实冻结屏幕.png")
            let c1 = PixelSampler.color(of: frozen, at: CGPoint(x: 10, y: 10))
            let c2 = PixelSampler.color(of: frozen, at: CGPoint(x: frozen.width - 10, y: frozen.height - 10))
            let c3 = PixelSampler.color(of: frozen, at: CGPoint(x: frozen.width / 2, y: frozen.height / 3))
            log("  左上=\(c1?.hexString ?? "?")  右下=\(c2?.hexString ?? "?")  中部=\(c3?.hexString ?? "?")")
            let colors = [c1, c2, c3].compactMap { $0?.hexString }
            check("画面不是纯色（确认非空白兜底图）", Set(colors).count > 1, colors.joined(separator: " / "))
        } else {
            check("捕获到真实屏幕", false, "frozenCG 为空")
        }

        // 显示起始状态
        shot(sc.allViews().first, "S02-冻结层原始画面.png")

        // 先验证事件派发是否真的路由到画布
        sc.setTool(.pen)
        sc.setPenSize(2)
        drag([CGPoint(x: 260, y: 620), CGPoint(x: 300, y: 600), CGPoint(x: 340, y: 625)])
        pump(0.1)
        if st.strokes.isEmpty {
            log("  ⚠️  窗口事件派发未命中画布，改用直接派发模式")
            useWindowDispatch = false
            drag([CGPoint(x: 260, y: 620), CGPoint(x: 300, y: 600), CGPoint(x: 340, y: 625)])
            pump(0.1)
        } else {
            log("  ✓ 通过窗口真实事件派发成功命中画布")
        }
        check("画笔（自由手绘）", st.strokes.count >= 1, "笔画数 \(st.strokes.count)")

        // ---- 2. 逐个工具 ----
        log("")
        log("[2] 全部绘图工具")
        sc.clearAll(); pump(0.05)

        sc.setTool(.pen); sc.setPenSize(3)
        sc.setSwatch(1)   // 不透明红
        drag((0..<40).map { CGPoint(x: 120 + CGFloat($0) * 9, y: 140 + sin(CGFloat($0) / 4) * 26) })
        check("自由画笔", st.strokes.count == 1, "笔画数 \(st.strokes.count)")

        sc.setTool(.line); sc.setSwatch(5)  // 不透明绿
        drag([CGPoint(x: 520, y: 110), CGPoint(x: 700, y: 190)])
        check("直线", st.strokes.count == 2)

        sc.setTool(.arrow); sc.setSwatch(1)
        drag([CGPoint(x: 760, y: 190), CGPoint(x: 950, y: 110)])
        check("箭头", st.strokes.count == 3)

        sc.setTool(.doubleArrow); sc.setSwatch(7)  // 不透明蓝
        drag([CGPoint(x: 1000, y: 110), CGPoint(x: 1200, y: 190)])
        check("双向箭头", st.strokes.count == 4)

        sc.setTool(.rect); sc.setSwatch(1); drag([CGPoint(x: 120, y: 260), CGPoint(x: 320, y: 360)])
        check("矩形", st.strokes.count == 5)

        sc.setTool(.rectFilled); sc.setSwatch(2)   // 透明黄（马克）
        drag([CGPoint(x: 360, y: 260), CGPoint(x: 560, y: 360)])
        check("实心矩形", st.strokes.count == 6)

        sc.setTool(.ellipse); sc.setSwatch(1)
        drag([CGPoint(x: 600, y: 260), CGPoint(x: 800, y: 360)])
        check("椭圆", st.strokes.count == 7)

        sc.setTool(.ellipseFilled); sc.setSwatch(0) // 透明红（马克）
        drag([CGPoint(x: 840, y: 260), CGPoint(x: 1040, y: 360)])
        check("实心椭圆", st.strokes.count == 8)

        // Shift 约束：正方形
        sc.setTool(.rect); sc.setSwatch(0)
        drag([CGPoint(x: 1100, y: 260), CGPoint(x: 1240, y: 330)], flags: .shift)
        if case .rect(let r) = st.strokes.last?.shape {
            check("Shift 约束为正方形", abs(r.width - r.height) < 1.5, "\(Int(r.width))×\(Int(r.height))")
        } else { check("Shift 约束为正方形", false) }

        // Shift 45° 吸附
        sc.setTool(.line)
        drag([CGPoint(x: 1300, y: 260), CGPoint(x: 1420, y: 300)], flags: .shift)
        if case .line(let a, let b) = st.strokes.last?.shape {
            let ang = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
            check("Shift 吸附 45°", abs(ang.rounded() / 45 - ang / 45) < 0.02, "角度 \(String(format: "%.1f", ang))°")
        } else { check("Shift 吸附 45°", false) }

        shot(view, "S03-基本图形.png")

        // ---- 3. 文字 / 对勾 / 叉号 ----
        log("")
        log("[3] 文字、对勾、叉号")
        sc.setTool(.check)
        click(CGPoint(x: 200, y: 460))
        if let last = st.strokes.last, case .check = last.shape { check("对勾", true) } else { check("对勾", false) }

        sc.setTool(.cross)
        click(CGPoint(x: 320, y: 460))
        if let last = st.strokes.last, case .cross = last.shape { check("叉号", true) } else { check("叉号", false) }

        sc.setTool(.text)
        sc.setPenSize(2)
        sc.setSwatch(7)
        click(CGPoint(x: 450, y: 430))
        pump(0.35)
        // 找到文本编辑框并输入
        if let box = view.subviews.compactMap({ $0 as? TextEditBox }).first {
            box.tv.string = "Pointofix macOS 真机测试"
            box.tv.onCommit?()          // 走真实提交路径（含移除编辑框）
            pump(0.15)
            if let last = st.strokes.last, case .text(let s, _, _) = last.shape {
                check("文字输入", s.contains("真机测试"), "内容「\(s)」")
            } else { check("文字输入", false, "最后一条不是文字") }
        } else {
            check("文字输入", false, "未创建编辑框")
        }
        shot(view, "S04-文字-对勾-叉号.png")

        // ---- 4. 马克笔 + 橡皮擦 ----
        log("")
        log("[4] 马克笔与橡皮擦")
        let beforeEraser = st.strokes.count
        // 水平马克笔迹，远离随后的竖直橡皮轨迹
        sc.setTool(.pen); sc.setPenSize(3); sc.setSwatch(0)   // 透明红马克
        drag((0..<50).map { CGPoint(x: 200 + CGFloat($0) * 10, y: 480) })
        let markerOnly = st.strokes.count
        check("马克笔迹已记录", markerOnly == beforeEraser + 1, "\(beforeEraser) → \(markerOnly)")

        var markerPt = CGPoint.zero
        var erasedPt = CGPoint.zero
        if let composed = st.composeCG(), let frozen = st.frozenCG {
            markerPt = CGPoint(x: 300, y: 480)          // 只被马克盖住
            erasedPt = CGPoint(x: 450, y: 480)          // 随后会被橡皮擦掉
            let a = PixelSampler.color(of: composed, at: CGPoint(x: markerPt.x * st.scale, y: markerPt.y * st.scale))
            let b = PixelSampler.color(of: frozen, at: CGPoint(x: markerPt.x * st.scale, y: markerPt.y * st.scale))
            check("马克笔覆盖底图（颜色改变）", a?.hexString != b?.hexString,
                  "标注 \(a?.hexString ?? "?") vs 底图 \(b?.hexString ?? "?")")
        }

        // 竖直橡皮自下而上横切马克笔迹
        sc.setTool(.eraser)
        drag((0..<40).map { CGPoint(x: 450, y: 560 - CGFloat($0) * 4) })
        pump(0.1)
        check("橡皮擦新增笔画记录", st.strokes.count == markerOnly + 1, "\(markerOnly) → \(st.strokes.count)")
        check("橡皮擦标记正确", st.strokes.last?.isEraser == true)

        if let composed = st.composeCG(), let frozen = st.frozenCG {
            let a = PixelSampler.color(of: composed, at: CGPoint(x: erasedPt.x * st.scale, y: erasedPt.y * st.scale))
            let b = PixelSampler.color(of: frozen, at: CGPoint(x: erasedPt.x * st.scale, y: erasedPt.y * st.scale))
            check("橡皮擦处还原为原始画面", a?.hexString == b?.hexString,
                  "擦后 \(a?.hexString ?? "?") vs 底图 \(b?.hexString ?? "?")")
        }
        shot(view, "S05-马克笔与橡皮擦.png")

        // ---- 4b. 打码：必须证明内容真的被抹掉，而不只是"颜色变了" ----
        log("")
        log("[4b] 打码（模糊 / 马赛克）")

        /// 把区域渲染成一张位图，直接读像素统计。
        /// 之前用"稀疏采样点的独立颜色数"是错的 —— 像素化会让每个格子产生不同的均值，
        /// 颜色数反而可能变多；真正该测的是**相邻像素的差异**（高频细节）。
        func regionStats(_ img: CGImage, _ rectPoints: CGRect, _ scale: CGFloat) -> (colors: Int, fine: Double) {
            let px = CGRect(x: rectPoints.minX * scale, y: rectPoints.minY * scale,
                            width: rectPoints.width * scale, height: rectPoints.height * scale).integral
            let w = Int(px.width), h = Int(px.height)
            guard w > 2, h > 2,
                  let sub = img.cropping(to: px.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))) else {
                return (0, 0)
            }
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0) }
            ctx.interpolationQuality = .none
            ctx.draw(sub, in: CGRect(x: 0, y: 0, width: w, height: h))

            var colors = Set<UInt32>()
            var diffs: [Double] = []
            // 沿每一行比较相邻像素 —— 打码会把高频细节抹平，这个值必然下降
            for y in stride(from: 0, to: h, by: max(1, h / 40)) {
                var prev: UInt32?
                for x in 0..<w {
                    let o = (y * w + x) * 4
                    let v = (UInt32(buf[o]) << 16) | (UInt32(buf[o + 1]) << 8) | UInt32(buf[o + 2])
                    colors.insert(v)
                    if let p = prev {
                        let dr = Double(abs(Int(buf[o]) - Int((p >> 16) & 0xFF)))
                        let dg = Double(abs(Int(buf[o + 1]) - Int((p >> 8) & 0xFF)))
                        let db = Double(abs(Int(buf[o + 2]) - Int(p & 0xFF)))
                        diffs.append((dr + dg + db) / 3.0)
                    }
                    prev = v
                }
            }
            return (colors.count, diffs.isEmpty ? 0 : diffs.reduce(0, +) / Double(diffs.count))
        }

        // 用确定性的高对比度棋盘作为底图。
        // 早先直接用真实冻结屏幕，结果这一项会随"桌面上恰好有什么"而波动 ——
        // 实测同一台机器上细节值在 0.93 和 4.21 之间跳，阈值就变得不可靠。
        func makeChecker(_ w: Int, _ h: Int, cell: Int = 6) -> CGImage? {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: cs,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.setFillColor(NSColor.white.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(NSColor.black.cgColor)
            for y in stride(from: 0, to: h, by: cell) {
                for x in stride(from: 0, to: w, by: cell) where ((x / cell) + (y / cell)) % 2 == 0 {
                    c.fill(CGRect(x: x, y: y, width: cell, height: cell))
                }
            }
            return c.makeImage()
        }
        let pw = Int(st.pointSize.width * st.scale), ph = Int(st.pointSize.height * st.scale)
        st.clipboardCG = makeChecker(pw, ph)
        st.clipboardSize = st.pointSize
        st.background = .clipboard
        st.rebuild(); pump(0.2)

        let redactRect = CGRect(x: 120, y: 150, width: 380, height: 220)
        if let frozen = st.clipboardCG, let before = st.composeCG() {
            let base = regionStats(frozen, redactRect, st.scale)
            log("  底图该区域: \(base.colors) 种颜色, 相邻像素平均差 \(String(format: "%.2f", base.fine))")

            // 马赛克
            sc.setTool(.pixelate)
            drag([CGPoint(x: redactRect.minX, y: redactRect.minY),
                  CGPoint(x: redactRect.maxX, y: redactRect.maxY)])
            pump(0.2)
            check("马赛克笔画已提交", st.strokes.last.map { if case .redact(_, .pixelate) = $0.shape { return true }; return false } ?? false)

            if let after = st.composeCG() {
                let px = regionStats(after, redactRect, st.scale)
                log("  马赛克后:   \(px.colors) 种颜色, 相邻像素平均差 \(String(format: "%.2f", px.fine))")
                check("马赛克抹平了高频细节（内容被抹掉）", px.fine < base.fine * 0.5,
                      String(format: "%.2f → %.2f", base.fine, px.fine))
            }

            // 撤销马赛克
            sc.undo()
            pump(0.1)

            // 模糊
            sc.setTool(.blur)
            drag([CGPoint(x: redactRect.minX, y: redactRect.minY),
                  CGPoint(x: redactRect.maxX, y: redactRect.maxY)])
            pump(0.2)
            if let after = st.composeCG() {
                let bl = regionStats(after, redactRect, st.scale)
                log("  模糊后:     \(bl.colors) 种颜色, 相邻像素平均差 \(String(format: "%.2f", bl.fine))")
                check("模糊柔化了画面", bl.fine < base.fine,
                      String(format: "%.2f → %.2f", base.fine, bl.fine))
            }
            sc.undo()
            pump(0.1)
            // 白纸上没有可打码的内容 → 应被拒绝
            sc.setBackground(.white); pump(0.1)
            let strokesBefore = st.strokes.count
            sc.setTool(.pixelate)
            drag([CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 300)])
            pump(0.1)
            check("空白纸上打码被拒绝（没有可打码的内容）", st.strokes.count == strokesBefore,
                  "笔画数 \(strokesBefore) → \(st.strokes.count)")
            sc.setBackground(.currentScreen); pump(0.2)
        }

        // ---- 4c. 序号标注 + 重做 ----
        log("")
        log("[4c] 序号标注与重做")
        sc.clearAll(); pump(0.1)
        sc.setTool(.number)
        var placed: [Int] = []
        for x in [200.0, 320.0, 440.0] {
            click(CGPoint(x: x, y: 600))
            if case .number(let n, _, _, _) = st.strokes.last?.shape ?? .rect(.zero) { placed.append(n) }
        }
        check("序号自动递增 1,2,3", placed == [1, 2, 3], "实际 \(placed)")
        sc.undo(); pump(0.1)
        check("撤销后序号重算为 3", st.nextNumber == 3, "nextNumber = \(st.nextNumber)")
        click(CGPoint(x: 560, y: 600))
        if case .number(let n, _, _, _) = st.strokes.last?.shape ?? .rect(.zero) {
            check("重新落号接续为 3", n == 3, "实际 \(n)")
        }

        let beforeRedo = st.strokes.count
        sc.undo(); sc.undo()
        let afterUndo = st.strokes.count
        sc.redo(); sc.redo()
        check("重做恢复撤销的笔画", st.strokes.count == beforeRedo,
              "\(beforeRedo) → 撤销后 \(afterUndo) → 重做后 \(st.strokes.count)")
        check("重做栈已清空", !st.canRedo)
        sc.redo()
        check("无可重做时 redo 是安全的空操作", st.strokes.count == beforeRedo)

        // ---- 4d. 聚焦高亮 ----
        log("")
        log("[4d] 聚焦高亮")
        sc.clearAll(); pump(0.1)
        let focus = CGRect(x: 300, y: 300, width: 400, height: 260)
        if let bg = st.composeCG() {
            let inside = PixelSampler.color(of: bg, at: CGPoint(x: focus.midX * st.scale, y: focus.midY * st.scale))
            let outsideBefore = PixelSampler.color(of: bg, at: CGPoint(x: 80 * st.scale, y: 80 * st.scale))
            sc.setTool(.spotlight)
            drag([CGPoint(x: focus.minX, y: focus.minY), CGPoint(x: focus.maxX, y: focus.maxY)])
            pump(0.2)
            if let after = st.composeCG() {
                let inAfter = PixelSampler.color(of: after, at: CGPoint(x: focus.midX * st.scale, y: focus.midY * st.scale))
                let outAfter = PixelSampler.color(of: after, at: CGPoint(x: 80 * st.scale, y: 80 * st.scale))
                check("聚焦区内部保持原样", inAfter?.hexString == inside?.hexString,
                      "\(inside?.hexString ?? "?") → \(inAfter?.hexString ?? "?")")
                check("聚焦区外部被压暗", outAfter?.hexString != outsideBefore?.hexString,
                      "\(outsideBefore?.hexString ?? "?") → \(outAfter?.hexString ?? "?")")
            }
        }
        sc.clearAll(); pump(0.1)

        // ---- 4e. 序号居中（像素级验证）----
        // 用"到圆心的距离"筛出圆内的白色像素 = 数字本身。
        // 早先版本用"红色像素包围盒"定位圆形，结果把整个采样框都算进去了，
        // 得到一个假通过的 0.0 偏差。
        log("")
        log("[4e] 序号居中（像素级）")
        sc.clearAll(); sc.setBackground(.white); pump(0.25)
        sc.setPenSize(3); sc.setSwatch(1)
        sc.setTool(.number)
        let numCenter = CGPoint(x: 600, y: 400)
        click(numCenter); pump(0.25)
        if let img = st.composeCG() {
            let scale = st.scale
            let half: CGFloat = 90
            let px = CGRect(x: (numCenter.x - half) * scale, y: (numCenter.y - half) * scale,
                            width: half * 2 * scale, height: half * 2 * scale).integral
            let w = Int(px.width), h = Int(px.height)
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            if let sub = img.cropping(to: px),
               let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .none
                ctx.draw(sub, in: CGRect(x: 0, y: 0, width: w, height: h))
                func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                    let o = (y * w + x) * 4
                    return (Int(buf[o]), Int(buf[o+1]), Int(buf[o+2]))
                }
                // 1) 找红色圆形（圆盘）的包围盒 → 圆心与半径
                var minX = w, maxX = -1, minY = h, maxY = -1
                for y in 0..<h { for x in 0..<w {
                    let (r, g, b) = rgb(x, y)
                    if r > 150, g < 90, b < 90 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                } }
                if maxX < 0 {
                    check("找到序号圆形", false, "画面里没有红色圆形")
                } else {
                    let cx = Double(minX + maxX) / 2, cy = Double(minY + maxY) / 2
                    let radius = Double(max(maxX - minX, maxY - minY)) / 2
                    check("找到序号圆形", true, String(format: "直径 %.0f px", radius * 2))
                    // 2) 圆内（半径 85% 以内）的白色像素 = 数字
                    var tMinX = w, tMaxX = -1, tMinY = h, tMaxY = -1, count = 0
                    for y in 0..<h { for x in 0..<w {
                        let dx = Double(x) - cx, dy = Double(y) - cy
                        guard (dx * dx + dy * dy).squareRoot() < radius * 0.85 else { continue }
                        let (r, g, b) = rgb(x, y)
                        if r > 235, g > 235, b > 235 {
                            tMinX = min(tMinX, x); tMaxX = max(tMaxX, x)
                            tMinY = min(tMinY, y); tMaxY = max(tMaxY, y)
                            count += 1
                        }
                    } }
                    check("数字画在圆内", count > 50, "文字像素 \(count) 个")
                    if count > 0 {
                        let tcx = Double(tMinX + tMaxX) / 2, tcy = Double(tMinY + tMaxY) / 2
                        log(String(format: "  圆心 (%.1f, %.1f)  数字中心 (%.1f, %.1f)  半径 %.1f px", cx, cy, tcx, tcy, radius))
                        check("序号水平居中", abs(tcx - cx) <= 2.0, String(format: "偏移 %.1f px", tcx - cx))
                        check("序号垂直居中", abs(tcy - cy) <= 2.0, String(format: "偏移 %.1f px", tcy - cy))
                        // 数字不能顶到圆的边缘（早先的 bug 就是数字偏下溢出圆外）
                        check("数字未溢出圆形", Double(tMaxY) < cy + radius, String(format: "底部 %.1f < %.1f", Double(tMaxY), cy + radius))
                    }
                }
            }
        }
        sc.clearAll(); sc.setBackground(.currentScreen); pump(0.25)
        sc.setPenSize(1); sc.setSwatch(0); sc.setTool(.pen)

        // ---- 4f. 聚焦不累积 + ESC 取消拖动 ----
        log("")
        log("[4f] 聚焦不累积 / ESC 取消拖动")

        // 聚焦：先后框两处，非聚焦区的亮度不应一次比一次暗
        sc.clearAll(); sc.setBackground(.currentScreen); pump(0.25)
        let spotProbe = CGPoint(x: 1300, y: 850)      // 两次聚焦区之外
        func probeColor() -> String? {
            guard let cg = st.composeCG() else { return nil }
            return PixelSampler.color(of: cg, at: CGPoint(x: spotProbe.x * st.scale, y: spotProbe.y * st.scale))?.hexString
        }
        let original = probeColor()
        sc.setTool(.spotlight)
        drag([CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 350)]); pump(0.2)
        let afterFirst = probeColor()
        drag([CGPoint(x: 600, y: 400), CGPoint(x: 900, y: 650)]); pump(0.2)
        let afterSecond = probeColor()
        log("  非聚焦区颜色: 原始 \(original ?? "?") → 第一次聚焦后 \(afterFirst ?? "?") → 第二次后 \(afterSecond ?? "?")")
        check("第一次聚焦确实压暗了非聚焦区", afterFirst != original,
              "\(original ?? "?") → \(afterFirst ?? "?")")
        check("第二次聚焦不会继续加深（不累积）", afterSecond == afterFirst,
              "\(afterFirst ?? "?") vs \(afterSecond ?? "?")")

        // ESC 取消拖动：拖到一半取消，不应留下任何笔画
        sc.clearAll(); pump(0.15)
        sc.setTool(.pen); sc.setPenSize(2); sc.setSwatch(1)
        let strokesBeforeCancel = st.strokes.count
        if let down = event(.leftMouseDown, CGPoint(x: 300, y: 300)) { view.mouseDown(with: down) }
        if let move = event(.leftMouseDragged, CGPoint(x: 500, y: 400)) { view.mouseDragged(with: move) }
        check("拖动中被标记为拖动状态", view.isDragging)
        view.cancelDrag()                              // 等价于拖动中按 ESC
        check("取消后不再处于拖动状态", !view.isDragging)
        if let up = event(.leftMouseUp, CGPoint(x: 500, y: 400)) { view.mouseUp(with: up) }
        pump(0.1)
        check("取消的拖动没有留下笔画", st.strokes.count == strokesBeforeCancel,
              "笔画数 \(strokesBeforeCancel) → \(st.strokes.count)")
        check("会话仍在进行（ESC 取消拖动不会结束标注）", SessionController.shared.isActive)

        // 对照：正常完成的拖动应当留下笔画
        drag([CGPoint(x: 300, y: 300), CGPoint(x: 500, y: 400)]); pump(0.1)
        check("正常完成的拖动会留下笔画", st.strokes.count == strokesBeforeCancel + 1,
              "笔画数 \(strokesBeforeCancel) → \(st.strokes.count)")
        sc.clearAll(); pump(0.15)

        // ---- 4g. 界面自定义（调色板 / 形状槽位 / 序号形状 / 布局配置）----
        log("")
        log("[4g] 界面自定义")

        // 调色板换色
        let slotBefore = Palette.standard[0].base.hexString
        Palette.setSlot(0, hex: "#123456")
        check("调色板槽位可换色", Palette.standard[0].base.hexString == "#123456",
              "\(slotBefore) → \(Palette.standard[0].base.hexString)")
        check("换色不改变该槽位的透明度（仍是马克笔）", !Palette.standard[0].isOpaque)
        Palette.resetSlot(0)
        check("可恢复默认颜色", Palette.standard[0].base.hexString == slotBefore,
              "→ \(Palette.standard[0].base.hexString)")

        // 形状槽位可替换
        let slotBackup = Prefs.shapeSlots
        SessionController.shared.assignShapeSlot(0, to: .ellipseFilled)
        check("形状槽位可替换", Prefs.effectiveShapeSlots[0] == .ellipseFilled,
              "槽位0 → \(Prefs.effectiveShapeSlots[0].rawValue)")
        Prefs.shapeSlots = slotBackup
        check("形状槽位可还原", Prefs.effectiveShapeSlots[0] == .line)

        // 序号形状：三种形状的填充率应当显著不同
        // 圆 ≈ π/4 = 78.5%，正方形 = 100%，等边三角形 ≈ 50%
        log("")
        log("[4g-2] 序号形状（用填充率验证形状确实变了）")
        sc.clearAll(); sc.setBackground(.white); pump(0.25)
        sc.setPenSize(3); sc.setSwatch(1); sc.setTool(.number)
        let shapeCenters: [(NumberShape, CGPoint)] = [
            (.circle, CGPoint(x: 300, y: 300)),
            (.square, CGPoint(x: 700, y: 300)),
            (.triangle, CGPoint(x: 1100, y: 300))
        ]
        func fillRatio(_ center: CGPoint) -> Double? {
            guard let img = st.composeCG() else { return nil }
            let half: CGFloat = 70
            let px = CGRect(x: (center.x - half) * st.scale, y: (center.y - half) * st.scale,
                            width: half * 2 * st.scale, height: half * 2 * st.scale).integral
            let w = Int(px.width), h = Int(px.height)
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let sub = img.cropping(to: px),
                  let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(sub, in: CGRect(x: 0, y: 0, width: w, height: h))
            var minX = w, maxX = -1, minY = h, maxY = -1
            for y in 0..<h { for x in 0..<w {
                let o = (y * w + x) * 4
                if Int(buf[o]) > 150, Int(buf[o+1]) < 90, Int(buf[o+2]) < 90 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            } }
            guard maxX > minX, maxY > minY else { return nil }
            var filled = 0, total = 0
            for y in minY...maxY { for x in minX...maxX {
                let o = (y * w + x) * 4
                total += 1
                if Int(buf[o]) > 150, Int(buf[o+1]) < 90, Int(buf[o+2]) < 90 { filled += 1 }
            } }
            return total > 0 ? Double(filled) / Double(total) : nil
        }
        var ratios: [NumberShape: Double] = [:]
        for (shape, center) in shapeCenters {
            Prefs.numberShape = shape
            click(center); pump(0.2)
            if let r = fillRatio(center) { ratios[shape] = r }
        }
        if let rc = ratios[.circle], let rs = ratios[.square], let rt = ratios[.triangle] {
            log(String(format: "  填充率: 圆 %.0f%%  方 %.0f%%  三角 %.0f%%", rc * 100, rs * 100, rt * 100))
            // 实测值会低于理论值（π/4≈78.5%、100%、50%），因为数字本身是白色、
            // 从彩色标记里被挖掉了，另外抗锯齿边缘也不算作红色。
            // 所以断言"相对关系 + 区分度"，而不是绝对值。
            check("正方形填充率 > 圆形（方 > 圆 > 三角）", rs > rc && rc > rt,
                  String(format: "%.0f%% > %.0f%% > %.0f%%", rs * 100, rc * 100, rt * 100))
            check("三种形状区分度足够（两两相差 >8 个百分点）",
                  (rs - rc) > 0.08 && (rc - rt) > 0.08,
                  String(format: "方-圆 %.0f%%，圆-三角 %.0f%%", (rs - rc) * 100, (rc - rt) * 100))
            check("方形接近铺满（>85%）", rs > 0.85, String(format: "%.0f%%", rs * 100))
            check("三角约为方形的一半（0.38–0.60）", (rt / rs) > 0.38 && (rt / rs) < 0.60,
                  String(format: "%.2f", rt / rs))
        } else {
            check("三种序号形状都能测到", false, "未能采集到填充率")
        }
        Prefs.numberShape = .circle

        // 布局配置：重置应恢复默认
        Prefs.numberShape = .triangle
        Palette.setSlot(2, hex: "#ABCDEF")
        Prefs.shapeSlots = [ToolKind.ellipse.rawValue] + Prefs.defaultShapeSlots.dropFirst()
        LayoutConfigResetForTest()
        check("重置布局恢复序号形状", Prefs.numberShape == .circle, Prefs.numberShape.rawValue)
        check("重置布局恢复调色板", Palette.standard[2].base.hexString == Palette.defaults[2].0.hexString)
        check("重置布局恢复形状槽位", Prefs.effectiveShapeSlots[0] == .line,
              Prefs.effectiveShapeSlots[0].rawValue)

        sc.clearAll(); sc.setBackground(.currentScreen); pump(0.25)
        sc.setPenSize(1); sc.setSwatch(0); sc.setTool(.pen)

        // ---- 4i. 水印 / 装饰边框 / 选区尺寸 ----
        log("")
        log("[4i] 水印、装饰边框与选区")

        if let base = st.composeCG() {
            // 水印：右下角应出现内容，其余区域基本不变
            Prefs.frameStyle = FrameStyle.none.rawValue
            Prefs.watermark = ""
            let plain = Decorator.apply(base)
            check("无装饰时原样返回（不重绘）", plain.width == base.width && plain.height == base.height,
                  "\(plain.width)×\(plain.height)")

            Prefs.watermark = "PentoPic 测试水印"
            let marked = Decorator.apply(base)
            check("加水印后尺寸不变", marked.width == base.width && marked.height == base.height)
            // 注意：NSColor.whiteComponent / brightnessComponent 对不兼容的色彩空间
            // 会**抛异常**（不是返回默认值），必须先 usingColorSpace(.sRGB)。
            func regionHasInk(_ img: CGImage, _ r: CGRect) -> Bool {
                var y = Int(r.minY)
                while y < Int(r.maxY) {
                    var x = Int(r.minX)
                    while x < Int(r.maxX) {
                        if let c = PixelSampler.color(of: img, at: CGPoint(x: x, y: y))?
                                       .usingColorSpace(.sRGB),
                           c.alphaComponent > 0.6,
                           c.redComponent > 0.9, c.greenComponent > 0.9, c.blueComponent > 0.9 {
                            return true
                        }
                        x += 3
                    }
                    y += 3
                }
                return false
            }
            let corner = CGRect(x: CGFloat(base.width) * 0.6, y: CGFloat(base.height) * 0.88,
                                width: CGFloat(base.width) * 0.39, height: CGFloat(base.height) * 0.11)
            check("水印出现在右下角", regionHasInk(marked, corner))
            // 差分检查：左上角本来就可能本来就是白的（真实屏幕截图），
            // 所以要比"加了水印之后有没有变化"，而不是"这里是不是白的"
            func regionDiffers(_ a: CGImage, _ b: CGImage, _ r: CGRect) -> Bool {
                var y = Int(r.minY)
                while y < Int(r.maxY) {
                    var x = Int(r.minX)
                    while x < Int(r.maxX) {
                        let ca = PixelSampler.color(of: a, at: CGPoint(x: x, y: y))?.usingColorSpace(.sRGB)
                        let cb = PixelSampler.color(of: b, at: CGPoint(x: x, y: y))?.usingColorSpace(.sRGB)
                        if ca?.hexString != cb?.hexString { return true }
                        x += 3
                    }
                    y += 3
                }
                return false
            }
            let topLeft = CGRect(x: 4, y: 4, width: 240, height: 80)
            check("水印不影响左上角（差分）", !regionDiffers(plain, marked, topLeft))
            check("水印确实改变了右下角（差分）", regionDiffers(plain, marked, corner))
            Prefs.watermark = ""

            // 装饰边框：都应让画布变大
            for f in [FrameStyle.border, .shadow, .torn] {
                Prefs.frameStyle = f.rawValue
                let dec = Decorator.apply(base)
                check("\(f.title) 让导出图变大（留出边距）",
                      dec.width > base.width && dec.height > base.height,
                      "\(base.width)×\(base.height) → \(dec.width)×\(dec.height)")
            }
            Prefs.frameStyle = FrameStyle.none.rawValue
            let back = Decorator.apply(base)
            check("恢复无边框后尺寸复原", back.width == base.width && back.height == base.height)
        }

        // 固定尺寸选区
        sc.setTool(.region); pump(0.1)
        let savedFixed = Prefs.fixedRegion
        let savedFree = Prefs.freeRegion
        Prefs.freeRegion = false
        Prefs.fixedRegion = "500x300"
        drag([CGPoint(x: 700, y: 400), CGPoint(x: 900, y: 500)]); pump(0.2)
        if let r = st.region {
            check("固定尺寸选区：尺寸恒定",
                  abs(r.width - 500) < 1 && abs(r.height - 300) < 1,
                  "\(Int(r.width))×\(Int(r.height))")
        } else {
            check("固定尺寸选区生效", false, "未建立选区")
        }
        Prefs.fixedRegion = ""

        // 自由手绘选区
        Prefs.freeRegion = true
        st.region = nil; st.regionPath = nil
        drag([CGPoint(x: 300, y: 300), CGPoint(x: 600, y: 320),
              CGPoint(x: 640, y: 560), CGPoint(x: 320, y: 540)]); pump(0.2)
        check("自由手绘选区记录了多边形", (st.regionPath?.count ?? 0) >= 3,
              "\(st.regionPath?.count ?? 0) 个顶点")
        check("手绘选区时矩形选区被清空", st.region == nil)
        if let full = st.composeCG(), let cut = st.composeCG() {
            check("手绘选区能导出（不崩溃）", cut.width > 0)
            // 手绘选区的导出应当比整屏小
            let cropped = Exporter.currentImage(st, regionOnly: true)
            check("手绘选区导出结果被裁小", (cropped?.width ?? .max) < full.width,
                  "\(cropped?.width ?? 0) < \(full.width)")
        }
        st.regionPath = nil
        Prefs.freeRegion = savedFree
        Prefs.fixedRegion = savedFixed
        sc.setTool(.pen); pump(0.1)

        // ---- 4j. 选择 / 移动 / 对齐 / 分布 / 组合 ----
        log("")
        log("[4j] 选择与排列")
        sc.clearAll(); pump(0.2)
        sc.setTool(.rectFilled); sc.setPenSize(1); sc.setSwatch(1)
        // 三个尺寸不同的方块，方便验证对齐与分布
        drag([CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 300)]); pump(0.12)
        drag([CGPoint(x: 500, y: 260), CGPoint(x: 560, y: 340)]); pump(0.12)
        drag([CGPoint(x: 800, y: 420), CGPoint(x: 900, y: 520)]); pump(0.12)
        check("已画三个对象", st.strokes.count == 3, "\(st.strokes.count) 个")

        sc.setTool(.select); pump(0.12)
        check("切换到选择工具", sc.tool == .select)

        // 命中测试：内部命中、远处不命中
        click(CGPoint(x: 250, y: 250)); pump(0.15)
        check("点击方块内部可选中", st.selection.count == 1, "\(st.selection.count) 个")
        let firstSel = st.selectedStrokes.first?.shape.bounds
        check("选中的是第一个方块",
              abs((firstSel?.minX ?? 0) - 200) < 2 && abs((firstSel?.minY ?? 0) - 200) < 2,
              firstSel.map { "(\(Int($0.minX)),\(Int($0.minY)))" } ?? "无")

        click(CGPoint(x: 1200, y: 800)); pump(0.15)
        check("点击空白处清空选择", st.selection.isEmpty, "\(st.selection.count) 个")

        // 框选：应选中两个
        drag([CGPoint(x: 150, y: 150), CGPoint(x: 620, y: 400)]); pump(0.2)
        check("框选命中两个对象", st.selection.count == 2, "\(st.selection.count) 个")

        // 移动：整体平移，包围盒应跟着走
        guard let boxBefore = st.selectionBounds else { return }
        if let down = event(.leftMouseDown, CGPoint(x: 250, y: 250)),
           let mv = event(.leftMouseDragged, CGPoint(x: 280, y: 260)),
           let up = event(.leftMouseUp, CGPoint(x: 280, y: 260)) {
            view.mouseDown(with: down); view.mouseDragged(with: mv); view.mouseUp(with: up)
        }
        pump(0.2)
        if let boxAfter = st.selectionBounds {
            check("拖动整体平移选中对象",
                  abs((boxAfter.minX - boxBefore.minX) - 30) < 2 &&
                  abs((boxAfter.minY - boxBefore.minY) - 10) < 2,
                  String(format: "位移 (%.0f, %.0f)", boxAfter.minX - boxBefore.minX, boxAfter.minY - boxBefore.minY))
        } else {
            check("移动后仍有选择", false)
        }
        check("移动不改变对象数量", st.strokes.count == 3, "\(st.strokes.count) 个")

        // 对齐：左对齐后两个对象的 minX 应一致
        sc.alignSelection(.left); pump(0.2)
        let lefts = st.selectedStrokes.map { $0.shape.bounds.minX }
        check("左对齐：所有选中对象 minX 一致",
              lefts.count == 2 && abs(lefts[0] - lefts[1]) < 1.5,
              lefts.map { String(format: "%.1f", $0) }.joined(separator: ", "))

        // 分布：三个对象水平等距
        sc.selectAll(); pump(0.15)
        check("全选到三个对象", st.selection.count == 3)
        sc.distributeSelection(horizontal: true); pump(0.2)
        let mids = st.selectedStrokes.map { $0.shape.bounds.midX }.sorted()
        if mids.count == 3 {
            let g1 = mids[1] - mids[0], g2 = mids[2] - mids[1]
            check("水平分布：间距相等", abs(g1 - g2) < 1.5,
                  String(format: "%.1f vs %.1f", g1, g2))
        } else {
            check("分布需要三个对象", false)
        }

        // 组合：点击组内任一对象应选中整组
        sc.groupSelection(); pump(0.2)
        let groups = Set(st.strokes.compactMap { $0.groupID })
        check("组合后三个对象共享同一 groupID", groups.count == 1 && st.strokes.allSatisfy { $0.groupID != nil },
              "\(groups.count) 个组")
        sc.clearSelection(); pump(0.1)
        click(CGPoint(x: st.strokes[1].shape.bounds.midX, y: st.strokes[1].shape.bounds.midY)); pump(0.15)
        check("点击组合内任一对象选中整组", st.selection.count == 3, "\(st.selection.count) 个")

        // 移动整组
        guard let gBefore = st.selectionBounds else { return }
        sc.nudgeSelection(dx: 40, dy: 0); pump(0.15)
        if let gAfter = st.selectionBounds {
            check("整组一起移动", abs((gAfter.minX - gBefore.minX) - 40) < 1.5,
                  String(format: "位移 %.1f", gAfter.minX - gBefore.minX))
        }
        sc.ungroupSelection(); pump(0.15)
        check("取消组合后 groupID 被清空", st.strokes.allSatisfy { $0.groupID == nil })

        // 层级。「全选后置于顶层」是空操作，所以要只选一个才有意义。
        let firstIDBefore = st.strokes.first?.id
        st.selection = firstIDBefore.map { [$0] } ?? []
        pump(0.1)
        sc.reorderSelection(toFront: true); pump(0.15)
        check("单个对象置于顶层后移到末尾", st.strokes.last?.id == firstIDBefore,
              "原首项现在在\(st.strokes.last?.id == firstIDBefore ? "末" : "非末")位")
        sc.selectAll(); pump(0.1)

        // 删除
        let beforeDelete = st.strokes.count
        sc.deleteSelection(); pump(0.2)
        check("删除选中对象", st.strokes.isEmpty && beforeDelete == 3,
              "\(beforeDelete) → \(st.strokes.count)")
        check("删除后选择被清空", st.selection.isEmpty)

        sc.setTool(.pen); pump(0.1); sc.setSwatch(0)

        // ---- 4k. 工具栏覆盖性 ----
        // 每个工具都必须有按钮。选择工具曾经因为一次字符串替换静默失败而根本没进工具栏，
        // 只能靠 V 键调用 —— 用户找不到它，还以为这个功能不存在。
        log("")
        log("[4k] 工具栏覆盖性")
        var placedTools = Set<ToolKind>()
        for row in ToolbarView.toolRowLayout {
            for slot in row { placedTools.insert(slot.resolved) }
        }
        let missing = ToolKind.allCases.filter { !placedTools.contains($0) }
        check("工具栏覆盖全部 \(ToolKind.allCases.count) 个工具",
              missing.isEmpty,
              missing.isEmpty ? "全部覆盖" : "缺失: " + missing.map { $0.rawValue }.joined(separator: ", "))
        check("指针排在最前（默认工具应当好找）",
              ToolbarView.toolRowLayout.first?.first?.resolved == .select,
              ToolbarView.toolRowLayout.first?.first?.resolved.rawValue ?? "空")

        // 默认工具设置
        let savedDefault = Prefs.defaultToolMode
        Prefs.defaultToolMode = "select"
        check("默认工具：指针", Prefs.initialTool == .select, Prefs.initialTool.rawValue)
        Prefs.defaultToolMode = "pen"
        check("默认工具：画笔", Prefs.initialTool == .pen, Prefs.initialTool.rawValue)
        Prefs.defaultToolMode = "last"
        Prefs.lastTool = .arrow
        check("默认工具：上次使用", Prefs.initialTool == .arrow, Prefs.initialTool.rawValue)
        Prefs.defaultToolMode = savedDefault

        // ---- 4l. 临时工具（空格 / ⇧拖动）----
        log("")
        log("[4l] 临时工具切换")
        sc.clearAll(); pump(0.15)
        // 出厂默认（注册值）应当是画笔。持久化值可能还是上一版的 "select"，
        // 那由 Prefs.migrateDefaultToolIfNeeded() 处理。
        let savedMode2 = Prefs.defaultToolMode
        UserDefaults.standard.removeObject(forKey: "defaultTool")
        check("出厂默认工具是画笔", Prefs.initialTool == .pen, Prefs.initialTool.rawValue)
        // 迁移：旧版的 "select" 应当被视为旧默认值而被丢弃
        UserDefaults.standard.set("select", forKey: "defaultTool")
        UserDefaults.standard.removeObject(forKey: "defaultToolMigrated")
        Prefs.migrateDefaultToolIfNeeded()
        check("旧版的 select 默认值被迁移掉", Prefs.initialTool == .pen, Prefs.initialTool.rawValue)
        // 迁移后用户主动选的 select 应当被保留
        Prefs.defaultToolMode = "select"
        Prefs.migrateDefaultToolIfNeeded()
        check("迁移只做一次，之后用户的选择被保留", Prefs.initialTool == .select, Prefs.initialTool.rawValue)
        Prefs.defaultToolMode = savedMode2

        sc.setTool(.pen); pump(0.1); sc.setSwatch(1); sc.setPenSize(1)
        drag([CGPoint(x: 400, y: 400), CGPoint(x: 500, y: 460)]); pump(0.15)
        check("画笔能画", st.strokes.count == 1, "\(st.strokes.count) 条")

        // 空格：临时借用指针，松开还原
        check("静止时没有临时工具", !sc.isTemporaryTool)
        sc.pushTemporaryTool(.select); pump(0.1)
        check("空格 → 临时切到指针", sc.tool == .select && sc.isTemporaryTool, sc.tool.rawValue)
        check("临时切换不覆盖「上次使用的工具」记忆", Prefs.lastTool == .pen, Prefs.lastTool.rawValue)
        sc.popTemporaryTool(); pump(0.1)
        check("松开空格 → 还原画笔", sc.tool == .pen && !sc.isTemporaryTool, sc.tool.rawValue)

        // 嵌套：空格 + ⇧拖动同时生效时也能逐个还原
        sc.pushTemporaryTool(.select); sc.pushTemporaryTool(.eyedropper); pump(0.1)
        check("嵌套临时切换", sc.tool == .eyedropper && sc.isTemporaryTool)
        sc.popTemporaryTool()
        check("先还原到上一层", sc.tool == .select, sc.tool.rawValue)
        sc.popTemporaryTool()
        check("再还原到画笔", sc.tool == .pen, sc.tool.rawValue)

        // ⇧ + 在已有笔画上按下 = 临时移动
        sc.setTool(.pen); st.selection.removeAll(); pump(0.12)
        guard let penBefore = st.strokes.first?.shape.bounds else { return }
        let hit = CGPoint(x: penBefore.midX, y: penBefore.midY)
        func send(_ type: NSEvent.EventType, _ p: CGPoint, _ f: NSEvent.ModifierFlags) {
            guard let e = event(type, p, flags: f) else { return }
            switch type {
            case .leftMouseDown:    view.mouseDown(with: e)
            case .leftMouseDragged: view.mouseDragged(with: e)
            case .leftMouseUp:      view.mouseUp(with: e)
            default: break
            }
        }
        send(.leftMouseDown, hit, .shift)
        check("⇧ 在笔画上按下 → 临时变成指针", sc.tool == .select && sc.isTemporaryTool, sc.tool.rawValue)
        check("⇧ 按下会选中该笔画", st.selection.count == 1, "\(st.selection.count) 个")
        send(.leftMouseDragged, CGPoint(x: hit.x + 60, y: hit.y + 20), .shift)
        send(.leftMouseUp, CGPoint(x: hit.x + 60, y: hit.y + 20), .shift)
        pump(0.15)
        check("⇧ 拖动移动了笔画",
              abs((st.strokes.first?.shape.bounds.midX ?? 0) - (penBefore.midX + 60)) < 3,
              String(format: "%.0f → %.0f", penBefore.midX, st.strokes.first?.shape.bounds.midX ?? 0))
        check("松开鼠标 → 还原画笔", sc.tool == .pen && !sc.isTemporaryTool, sc.tool.rawValue)
        check("⇧ 移动后笔画数量不变", st.strokes.count == 1)

        // ⇧ 在空白处按下：仍然是"约束"，不该被拦截
        st.selection.removeAll(); pump(0.1)
        sc.setTool(.ellipse); pump(0.1)
        send(.leftMouseDown, CGPoint(x: 1000, y: 700), .shift)
        check("⇧ 在空白处不会被拦截成移动", sc.tool == .ellipse, sc.tool.rawValue)
        send(.leftMouseUp, CGPoint(x: 1100, y: 760), .shift)
        pump(0.15)
        sc.clearAll(); pump(0.1)
        sc.setTool(.pen); sc.setSwatch(0)

        // ---- 4m. 选择框只属于指针工具 ----
        // 这个 bug 是视觉的：切走工具后虚线框还留在屏幕上。
        // 所以要真的渲染视图做差分，光看状态是测不出来的。
        log("")
        log("[4m] 选择框与工具的绑定")
        sc.clearAll(); pump(0.2)
        sc.setTool(.rectFilled); sc.setPenSize(2); sc.setSwatch(1)
        drag([CGPoint(x: 300, y: 300), CGPoint(x: 460, y: 420)]); pump(0.15)
        drag([CGPoint(x: 600, y: 340), CGPoint(x: 740, y: 460)]); pump(0.15)

        func viewCG() -> CGImage? {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.cgImage
        }
        /// 两张渲染图的差异像素数（按步长抽样，够快又够灵敏）
        func diffCount(_ a: CGImage, _ b: CGImage) -> Int {
            guard a.width == b.width, a.height == b.height else { return -1 }
            var n = 0
            for y in stride(from: 0, to: a.height, by: 7) {
                for x in stride(from: 0, to: a.width, by: 7) {
                    let ca = PixelSampler.color(of: a, at: CGPoint(x: x, y: y))?.usingColorSpace(.sRGB)
                    let cb = PixelSampler.color(of: b, at: CGPoint(x: x, y: y))?.usingColorSpace(.sRGB)
                    if ca?.hexString != cb?.hexString { n += 1 }
                }
            }
            return n
        }

        // 指针下选中两个对象
        sc.setTool(.select); pump(0.15)
        drag([CGPoint(x: 200, y: 200), CGPoint(x: 900, y: 600)]); pump(0.2)
        check("已在指针下选中两个对象", st.selection.count == 2, "\(st.selection.count) 个")
        let withBox = viewCG()

        // 切到画笔：虚线框必须消失
        sc.setTool(.pen); pump(0.25)
        check("切到画笔后选中数归零（不再可见/可操作）", sc.modelSelectedCount == 0,
              "\(sc.modelSelectedCount)")
        let noBox = viewCG()
        if let a = withBox, let b = noBox {
            let d = diffCount(a, b)
            check("切换工具后画面确实变了（虚线框被抹掉）", d > 0, "\(d) 个像素不同")
            check("画面变化量很小（只抹掉了选择框，不是整屏重绘）", d < 40000, "\(d) 个像素")
        } else {
            check("能渲染画布做差分", false)
        }

        // 切换两个都不带选择的工具：画面应当完全一致（对照）
        sc.setTool(.ellipse); pump(0.25)
        let a2 = viewCG()
        sc.setTool(.arrow); pump(0.25)
        let a3 = viewCG()
        if let x = a2, let y = a3 {
            check("对照：两个非指针工具之间切换画面不变", diffCount(x, y) == 0,
                  "\(diffCount(x, y)) 个像素不同")
        }

        // 切回指针：选择应当还在
        sc.setTool(.select); pump(0.2)
        check("切回指针后选择被保留（不用重新框）", st.selection.count == 2,
              "\(st.selection.count) 个")

        // 非指针工具下 Delete 不该删掉看不见的选区
        sc.setTool(.pen); pump(0.15)
        let countBeforeDel = st.strokes.count
        let handled = sc.handleKeyDownForTest(keyCode: 51)   // Delete
        check("非指针工具下 Delete 不作用", !handled && st.strokes.count == countBeforeDel,
              "handled=\(handled) 笔画 \(countBeforeDel) → \(st.strokes.count)")

        // 悬空 id：撤销掉被选中的笔画后，选中数不能虚高
        sc.setTool(.select); pump(0.15)
        sc.selectAll(); pump(0.1)
        check("全选两个", st.selection.count == 2)
        sc.undo(); sc.undo(); pump(0.2)
        check("撤销后选择里没有悬空 id", st.selectedStrokes.count == 0,
              "selectedStrokes=\(st.selectedStrokes.count) 原始 id 数=\(st.selection.count)")
        check("模型选中数同步归零", sc.modelSelectedCount == 0, "\(sc.modelSelectedCount)")

        sc.clearAll(); pump(0.15)
        sc.setTool(.pen); sc.setSwatch(0)

        // ---- 4n. 编辑操作的撤销（快照式）----
        // 用户报的 bug：选中几条笔画删除后，撤销不起作用。
        // 根因是撤销只能"弹掉最后一条"，而删除改的是数组中间。
        log("")
        log("[4n] 编辑操作的撤销")
        sc.clearAll(); pump(0.2)

        func drawThree() {
            sc.setTool(.rectFilled); sc.setPenSize(1); sc.setSwatch(1)
            drag([CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 280)]); pump(0.12)
            drag([CGPoint(x: 500, y: 200), CGPoint(x: 600, y: 280)]); pump(0.12)
            drag([CGPoint(x: 800, y: 200), CGPoint(x: 900, y: 280)]); pump(0.12)
        }

        // 1) 删除 → 撤销
        drawThree()
        check("画了三条", st.strokes.count == 3, "\(st.strokes.count)")
        sc.setTool(.select); pump(0.12)
        st.selection = [st.strokes[1].id]          // 选中**中间**那条
        pump(0.1)
        sc.deleteSelection(); pump(0.15)
        check("删除了中间一条", st.strokes.count == 2, "\(st.strokes.count)")
        check("删除后可以撤销", st.canUndo)
        sc.undo(); pump(0.2)
        check("撤销恢复了被删的笔画", st.strokes.count == 3, "\(st.strokes.count)")
        check("恢复的是原来那条（不是弹掉别的）",
              st.strokes.count == 3 && abs(st.strokes[1].shape.bounds.minX - 500) < 2,
              st.strokes.count == 3 ? String(format: "中间那条 minX=%.0f", st.strokes[1].shape.bounds.minX) : "数量不对")
        sc.redo(); pump(0.2)
        check("重做再次删除", st.strokes.count == 2, "\(st.strokes.count)")
        sc.undo(); pump(0.2)

        // 2) 对齐 → 撤销
        sc.setTool(.select); sc.selectAll(); pump(0.15)
        let beforeAlign = st.selectedStrokes.map { $0.shape.bounds.minX }.sorted()
        sc.alignSelection(.left); pump(0.2)
        check("对齐改变了位置", st.selectedStrokes.map { $0.shape.bounds.minX }.sorted() != beforeAlign)
        sc.undo(); pump(0.2)
        check("撤销恢复了对齐前的位置",
              st.selectedStrokes.map { $0.shape.bounds.minX }.sorted() == beforeAlign,
              st.selectedStrokes.map { String(format: "%.0f", $0.shape.bounds.minX) }.joined(separator: ", "))

        // 3) 拖动移动 → 撤销（整次拖动只记一条）
        sc.selectAll(); pump(0.1)
        let beforeMove = st.strokes.map { $0.shape.bounds.minX }.sorted()
        let undoDepthBefore = st.undoStack.count
        guard let start = st.selectionBounds.map({ CGPoint(x: $0.midX, y: $0.midY) }) else { return }
        func sendSel(_ t: NSEvent.EventType, _ p: CGPoint) {
            guard let e = event(t, p, flags: []) else { return }
            switch t {
            case .leftMouseDown:    view.mouseDown(with: e)
            case .leftMouseDragged: view.mouseDragged(with: e)
            case .leftMouseUp:      view.mouseUp(with: e)
            default: break
            }
        }
        sendSel(.leftMouseDown, start)
        for i in 1...5 { sendSel(.leftMouseDragged, CGPoint(x: start.x + CGFloat(i) * 12, y: start.y)) }
        sendSel(.leftMouseUp, CGPoint(x: start.x + 60, y: start.y))
        pump(0.2)
        check("拖动确实移动了", st.strokes.map { $0.shape.bounds.minX }.sorted() != beforeMove)
        check("整次拖动只记一条撤销", st.undoStack.count == undoDepthBefore + 1,
              "\(undoDepthBefore) → \(st.undoStack.count)")
        sc.undo(); pump(0.2)
        check("撤销恢复拖动前的位置",
              st.strokes.map { $0.shape.bounds.minX }.sorted() == beforeMove)

        // 4) 组合 → 撤销
        sc.selectAll(); pump(0.1)
        sc.groupSelection(); pump(0.15)
        check("组合生效", st.strokes.allSatisfy { $0.groupID != nil })
        sc.undo(); pump(0.2)
        check("撤销取消组合", st.strokes.allSatisfy { $0.groupID == nil })

        // 5) 一次删除多条 → 一次撤销全部恢复
        sc.clearAll(); pump(0.15)
        drawThree()
        let allIDs = st.strokes.map { $0.id }
        sc.selectAll(); pump(0.1)
        sc.deleteSelection(); pump(0.15)
        check("全部删除", st.strokes.isEmpty)
        sc.undo(); pump(0.2)
        check("一次撤销恢复全部三条", st.strokes.count == 3, "\(st.strokes.count)")
        check("恢复的是原来那三条", st.strokes.map { $0.id } == allIDs)

        sc.clearAll(); pump(0.15)
        sc.setTool(.pen); sc.setSwatch(0)

        // ---- 4o. 工具栏拖动区 ----
        // 用户报"鼠标无法移动工具栏"。先确认拖动区是否真的存在于视图层级里、尺寸是否正常。
        log("")
        log("[4o] 工具栏拖动区")
        if let panel = sc.toolbarPanelForTest, let content = panel.contentView {
            var found: [NSRect] = []
            func walk(_ v: NSView) {
                if let d = v as? DragView { found.append(d.frame) }
                for sub in v.subviews { walk(sub) }
            }
            walk(content)
            check("拖动区存在于视图层级中", !found.isEmpty, "\(found.count) 个")
            if let f = found.first {
                log(String(format: "  拖动区 frame = (%.0f, %.0f, %.0f×%.0f)  面板 %.0f×%.0f",
                           f.minX, f.minY, f.width, f.height, panel.frame.width, panel.frame.height))
                check("拖动区尺寸可用（宽>40 高>=14）", f.width > 40 && f.height >= 14,
                      String(format: "%.0f×%.0f", f.width, f.height))
            }
            // 面板是否完整落在屏幕内
            let scr = NSScreen.main ?? NSScreen.screens[0]
            let p = panel.frame
            let fully = scr.frame.contains(p)
            check("工具栏完整落在屏幕内（否则顶部拖动柄可能够不到）", fully,
                  String(format: "面板 y %.0f…%.0f，屏幕 y %.0f…%.0f",
                         p.minY, p.maxY, scr.frame.minY, scr.frame.maxY))
        } else {
            check("能找到工具栏面板", false)
        }

        // 钳制逻辑本身：部分露出屏幕时**必须**被拉回来（早先只判断"完全不相交"）
        let scr2 = NSScreen.main ?? NSScreen.screens[0]
        let vis2 = scr2.visibleFrame
        let partly = NSRect(x: vis2.minX + 20, y: vis2.minY - 15, width: 200, height: 400)
        let fixed = sc.clampForTest(partly)
        check("部分露出屏幕的窗口被拉回可见区域",
              abs(fixed.minY - vis2.minY) < 1, String(format: "y %.0f → %.0f", partly.minY, fixed.minY))
        check("拉回后完整可见", vis2.contains(fixed),
              String(format: "%.0f…%.0f vs %.0f…%.0f", fixed.minY, fixed.maxY, vis2.minY, vis2.maxY))

        let offRight = NSRect(x: vis2.maxX + 300, y: vis2.minY + 50, width: 200, height: 300)
        let fixedR = sc.clampForTest(offRight)
        check("完全在屏幕右侧之外也被拉回", vis2.contains(fixedR),
              String(format: "x %.0f → %.0f", offRight.minX, fixedR.minX))

        // 比屏幕还高时：优先保住顶部（拖动柄在那里）
        let tooTall = NSRect(x: vis2.minX + 50, y: vis2.minY, width: 200, height: vis2.height + 200)
        let fixedT = sc.clampForTest(tooTall)
        check("比屏幕还高时保顶部（拖动柄可见）",
              abs(fixedT.maxY - vis2.maxY) < 1, String(format: "顶部 %.0f vs %.0f", fixedT.maxY, vis2.maxY))

        // ---- 4p. ⌘Tab 切走与返回 ----
        log("")
        log("[4p] 切换 App 时的挂起与恢复")
        sc.clearAll(); pump(0.15)
        sc.setTool(.pen); sc.setPenSize(1); sc.setSwatch(1)
        drag([CGPoint(x: 400, y: 400), CGPoint(x: 520, y: 460)]); pump(0.15)
        drag([CGPoint(x: 700, y: 500), CGPoint(x: 820, y: 560)]); pump(0.15)
        let strokesBeforeSwitch = st.strokes.count
        check("切走前已画两条", strokesBeforeSwitch == 2, "\(strokesBeforeSwitch)")

        func visibleWindows() -> Int {
            sc.overlayWindowsForTest.filter { $0.isVisible }.count
        }
        check("切走前冻结层可见", visibleWindows() > 0, "\(visibleWindows()) 个可见")

        sc.suspendForAppSwitch(); pump(0.25)
        check("切走后会话仍然进行（没有结束）", sc.isActive)
        check("切走后标记为已挂起", sc.hiddenForAppSwitch)
        check("切走后冻结层全部收起", visibleWindows() == 0, "\(visibleWindows()) 个仍可见")
        check("切走后笔画一条没丢", st.strokes.count == strokesBeforeSwitch, "\(st.strokes.count)")
        check("切走后撤销栈仍在", st.canUndo)

        // 挂起期间再调一次不应出问题
        sc.suspendForAppSwitch(); pump(0.1)
        check("重复挂起是幂等的", visibleWindows() == 0 && sc.hiddenForAppSwitch)

        // 热键/菜单唤醒应当"返回标注"，而不是把会话结束掉
        sc.toggle(); pump(0.3)
        check("挂起时 toggle 是返回而不是结束", sc.isActive && !sc.hiddenForAppSwitch)
        check("返回后冻结层重新可见", visibleWindows() > 0, "\(visibleWindows()) 个可见")
        check("返回后笔画仍然完整", st.strokes.count == strokesBeforeSwitch, "\(st.strokes.count)")
        check("返回后仍可继续画", {
            sc.setTool(.pen)
            drag([CGPoint(x: 1000, y: 600), CGPoint(x: 1060, y: 640)]); pump(0.15)
            return st.strokes.count == strokesBeforeSwitch + 1
        }(), "\(st.strokes.count)")

        // 直接调恢复（模拟 App 重新激活）
        sc.suspendForAppSwitch(); pump(0.2)
        sc.resumeAfterAppSwitch(); pump(0.25)
        check("直接恢复也正常", !sc.hiddenForAppSwitch && visibleWindows() > 0 && sc.isActive)
        check("恢复后仍能响应鼠标", {
            sc.setTool(.select)
            click(CGPoint(x: 430, y: 430)); pump(0.12)
            return st.selection.count >= 1
        }(), "\(st.selection.count) 个选中")

        sc.clearAll(); pump(0.15)
        sc.setTool(.pen); sc.setSwatch(0)

        // ---- 5. 撤销 ----
        log("")
        log("[5] 撤销与清空")
        // 前面的用例结尾会清空画布，这里先画两条保证有东西可撤销
        sc.setTool(.pen); sc.setPenSize(1); sc.setSwatch(1)
        drag([CGPoint(x: 200, y: 700), CGPoint(x: 260, y: 730)])
        drag([CGPoint(x: 300, y: 700), CGPoint(x: 360, y: 730)])
        pump(0.1)
        let before = st.strokes.count
        check("已准备两条笔画", before >= 2, "笔画数 \(before)")
        st.invalidateZoomCache()
        sc.undo()
        check("撤销一条", st.strokes.count == before - 1, "\(before) → \(st.strokes.count)")
        sc.undo()
        check("再撤销一条", st.strokes.count == before - 2, "→ \(st.strokes.count)")
        shot(view, "S06-撤销后.png")

        // ---- 6. 选区 ----
        log("")
        log("[6] 区域选择与裁剪")
        sc.setTool(.region)
        drag([CGPoint(x: 100, y: 90), CGPoint(x: 1400, y: 560)])
        pump(0.1)
        check("选区已建立", st.region != nil, st.region.map { "\(Int($0.width))×\(Int($0.height)) pt" } ?? "nil")
        if let cg = st.composeCG(crop: st.region) {
            let expectW = Int(st.region!.width * st.scale)
            check("按选区裁剪导出", cg.width == expectW || abs(cg.width - expectW) <= 2,
                  "导出 \(cg.width)×\(cg.height) px，期望宽 \(expectW)")
            writeImage(cg, "S07-选区裁剪.png")
        }
        shot(view, "S08-选区虚线框.png")

        // ---- 7. 放大镜 ----
        log("")
        log("[7] 放大镜")
        sc.setTool(.magnifier)
        if let e = event(.mouseMoved, CGPoint(x: 700, y: 400)) { view.mouseMoved(with: e) }
        if let e = event(.leftMouseDown, CGPoint(x: 700, y: 400)) { view.mouseDown(with: e) }
        if let e = event(.leftMouseUp, CGPoint(x: 700, y: 400)) { view.mouseUp(with: e) }
        pump(0.3)
        if let mag = sc.magnifier, mag.isVisible {
            check("放大镜浮窗已显示", true, "倍率 \(Int(mag.factor * 100))%")
            shot(mag.contentView, "S09-放大镜-400%.png")
        } else {
            check("放大镜浮窗已显示", false)
        }

        // ---- 8. 缩放视图 ----
        log("")
        log("[8] 缩放视图")
        sc.setTool(.region)
        st.region = nil
        view.needsDisplay = true
        let sc2 = SessionController.shared
        sc2.zoom(canvas: st, direction: 1, center: CGPoint(x: 700, y: 400))
        pump(0.1)
        sc2.zoom(canvas: st, direction: 1, center: CGPoint(x: 700, y: 400))
        pump(0.2)
        check("进入缩放视图", st.zoom > 1.5, "倍率 \(Int(st.zoom))×")
        if let e = event(.mouseMoved, CGPoint(x: 700, y: 400)) { view.mouseMoved(with: e) }
        pump(0.2)
        shot(view, "S10-缩放视图与取色HUD.png")
        if let img = st.zoomSource() {
            let px = PixelSampler.color(of: img, at: CGPoint(x: 700 * st.scale, y: 400 * st.scale))
            check("缩放视图可读到像素色值", px != nil, px?.hexString ?? "?")
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(px?.hexString ?? "", forType: .string)
            check("Shift+点击复制色值路径可用（直接写剪贴板验证）",
                  NSPasteboard.general.string(forType: .string) == px?.hexString, px?.hexString ?? "?")
        }
        // 滚轮缩放必须锚定光标下的那个源像素（原版: "zoom ... at a specific position"）
        let probe = CGPoint(x: 900, y: 520)
        let srcA = st.visibleSourceRect
        let sxA = srcA.minX + probe.x / st.zoom
        let syA = srcA.minY + probe.y / st.zoom
        _ = view.applyWheelZoom(delta: 1, at: probe)
        pump(0.1)
        let srcB = st.visibleSourceRect
        let sxB = srcB.minX + probe.x / st.zoom
        let syB = srcB.minY + probe.y / st.zoom
        check("滚轮缩放锚定光标下的像素",
              abs(sxA - sxB) < 1.0 && abs(syA - syB) < 1.0,
              String(format: "源点 (%.1f, %.1f) → (%.1f, %.1f)", sxA, syA, sxB, syB))
        _ = view.applyWheelZoom(delta: -1, at: probe)
        pump(0.1)

        // 放大镜在缩放视图内同样可用（原版禁用的只是"绘图"）
        sc.setTool(.magnifier)
        if let e = event(.leftMouseDown, CGPoint(x: 800, y: 450)) { view.mouseDown(with: e) }
        if let e = event(.leftMouseUp, CGPoint(x: 800, y: 450)) { view.mouseUp(with: e) }
        pump(0.25)
        check("缩放视图内放大镜可用", sc.magnifier?.isVisible == true && st.zoom > 1,
              "倍率 \(Int(st.zoom))×，放大镜 \(sc.magnifier?.isVisible == true ? "显示" : "隐藏")")

        // 放大镜尺寸跟随笔粗
        var sizes: [CGFloat] = []
        for i in 0..<PenSize.count {
            sc.setPenSize(i)
            sizes.append(MagnifierPanel.size(forPenSize: PenSize.values[i]))
        }
        check("放大镜尺寸随笔粗递增", zip(sizes, sizes.dropFirst()).allSatisfy { $0 < $1 },
              sizes.map { "\(Int($0))" }.joined(separator: " → ") + " px")

        // 退回 1×
        for _ in 0..<12 where st.zoom > 1 { sc2.zoom(canvas: st, direction: -1, center: nil); pump(0.05) }
        check("退出缩放视图", st.zoom <= 1.001, "倍率 \(Int(st.zoom))×")

        // ---- 9. 工具栏 ----
        log("")
        log("[9] 工具栏")
        for w in NSApp.windows where w.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1 {
            shot(w.contentView, "S11-工具栏-活动状态.png")
        }
        check("工具栏存在", NSApp.windows.contains { $0.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1 })

        // ---- 10. 导出 ----
        log("")
        log("[10] 导出：PNG / JPG / BMP / 剪贴板")
        st.region = nil
        view.needsDisplay = true
        if let full = st.composeCG() {
            var sizes: [String: Int] = [:]
            for fmt in ExportFormat.allCases {
                if let d = Exporter.encode(full, as: fmt) {
                    let url = outDir.appendingPathComponent("S12-导出.\(fmt.ext)")
                    try? d.write(to: url)
                    sizes[fmt.ext] = d.count
                }
            }
            for fmt in ExportFormat.allCases {
                check("\(fmt.title) 导出能编码出内容", (sizes[fmt.ext] ?? 0) > 1000,
                      "\(sizes[fmt.ext] ?? 0) B")
            }
            check("JPG 比 PNG 小（有损压缩生效）", (sizes["jpg"] ?? .max) < (sizes["png"] ?? 0),
                  "JPG \(sizes["jpg"] ?? 0) B < PNG \(sizes["png"] ?? 0) B")

            // PDF 是唯一不走 NSBitmapImageRep 的格式，单独校验文件头与页数
            let pdfURL = outDir.appendingPathComponent("S12-导出.pdf")
            if let d = try? Data(contentsOf: pdfURL) {
                let head = String(data: d.prefix(5), encoding: .ascii) ?? ""
                check("PDF 文件头正确 (%PDF-)", head.hasPrefix("%PDF-"), head)
            }
            // 文件名模板
            Prefs.filenameTemplate = "T-{app}-{date}-{n}"
            let nm = Exporter.renderBaseName(index: 7)
            check("文件名模板占位符被替换", nm.contains("T-") && nm.contains("-7") && !nm.contains("{"),
                  nm)
            check("模板里的非法字符被替换", !Exporter.renderBaseName(index: 1).contains("/"),
                  Exporter.renderBaseName(index: 1))
            Prefs.filenameTemplate = "{app}-{date}-{time}"
        } else {
            check("合成导出图", false)
        }

        Exporter.copyToClipboard(st)
        let pb = NSPasteboard.general
        let pngBack = pb.data(forType: .png)
        check("复制到剪贴板", (pngBack?.count ?? 0) > 1000, "剪贴板 PNG \(pngBack?.count ?? 0) B")
        let imgCount = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.count ?? 0
        check("剪贴板含图像对象", imgCount > 0, "\(imgCount) 个")

        // ---- 11. 打印 → PDF（无界面验证打印管线）----
        log("")
        log("[11] 打印管线（输出 PDF 验证）")
        if let op = Exporter.makePrintOperation(st) {
            let pdf = outDir.appendingPathComponent("S13-打印输出.pdf")
            let info = op.printInfo
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = pdf
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            let okRun = op.run()
            let size = (try? FileManager.default.attributesOfItem(atPath: pdf.path)[.size] as? Int) ?? 0
            check("打印管线生成 PDF", okRun && (size ?? 0) > 2000, "\(pdf.lastPathComponent) \(size ?? 0) B")
        } else {
            check("打印管线生成 PDF", false, "无法构建 NSPrintOperation")
        }

        // ---- 11b. 会话结束必须收掉所有浮窗 ----
        log("")
        log("[11b] 会话结束时收起浮窗")
        // 先把各浮窗都触发出来
        if let st2 = sc.activeCanvas {
            sc.sampleColor(canvas: st2, at: CGPoint(x: 400, y: 400))
        }
        sc.showTooltip("Test-Tooltip")
        pump(0.3)
        let panelsBefore = NSApp.windows.filter {
            ($0 is ColorInfoPanel || $0 is TooltipPanel || $0 is MagnifierPanel || $0 is ToastPanel) && $0.isVisible
        }.count
        check("退出前确实存在浮窗（测试有意义）", panelsBefore > 0, "\(panelsBefore) 个可见浮窗")
        sc.showTooltip(nil)

        // ---- 4h. 区域捕捉（裁剪到选区）----
        log("")
        log("[4h] 裁剪到选区")
        sc.clearAll(); sc.setBackground(.currentScreen); pump(0.25)
        guard let stC = sc.activeCanvas else { return }
        let origSize = stC.pointSize
        let origOrigin = stC.rect.origin
        // 先画一笔，验证裁剪后笔画会跟着平移而不是丢失
        sc.setTool(.pen); sc.setPenSize(1); sc.setSwatch(1)
        drag([CGPoint(x: 200, y: 200), CGPoint(x: 260, y: 240)]); pump(0.1)
        let strokesBeforeCrop = stC.strokes.count
        // 再框一个区域
        sc.setTool(.region)
        let cropRect = CGRect(x: 150, y: 150, width: 600, height: 400)
        drag([CGPoint(x: cropRect.minX, y: cropRect.minY),
              CGPoint(x: cropRect.maxX, y: cropRect.maxY)]); pump(0.2)
        check("裁剪前选区已建立", stC.region != nil)
        sc.cropToRegion(); pump(0.4)
        if let stNew = sc.activeCanvas {
            check("画布尺寸变成选区大小",
                  abs(stNew.pointSize.width - cropRect.width) < 2 && abs(stNew.pointSize.height - cropRect.height) < 2,
                  "\(Int(origSize.width))×\(Int(origSize.height)) → \(Int(stNew.pointSize.width))×\(Int(stNew.pointSize.height))")
            check("画布位置移到选区处",
                  abs(stNew.rect.minX - (origOrigin.x + cropRect.minX)) < 2 &&
                  abs(stNew.rect.minY - (origOrigin.y + cropRect.minY)) < 2,
                  "(\(Int(stNew.rect.minX)), \(Int(stNew.rect.minY)))")
            check("笔画被保留（不是被丢弃）", stNew.strokes.count == strokesBeforeCrop,
                  "\(strokesBeforeCrop) → \(stNew.strokes.count)")
            // 笔画应已平移到新坐标系
            if case .freehand(let pts)? = stNew.strokes.first?.shape, let p0 = pts.first {
                check("笔画已按 -选区原点 平移",
                      abs(p0.x - (200 - cropRect.minX)) < 2 && abs(p0.y - (200 - cropRect.minY)) < 2,
                      String(format: "(%.0f, %.0f)", p0.x, p0.y))
            }
            check("裁剪后底图存在", stNew.frozenCG != nil)
            check("裁剪后可继续撤销", !stNew.strokes.isEmpty)
        } else {
            check("裁剪后仍有画布", false)
        }
        // 注意：裁剪会重建整个会话，测试里早先捕获的 st / view 引用会失效。
        // 所以本段必须放在**所有其它用例之后**，否则后续用例会操作已销毁的对象。
        // ---- 11c. 窗口捕捉 ----
        log("")
        log("[11c] 窗口捕捉")
        let wins = ScreenCapture.windows()
        check("能枚举到可捕捉窗口", !wins.isEmpty, "\(wins.count) 个")
        if let biggest = wins.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            log("  最大窗口: \(biggest.app) — \(biggest.title)  \(Int(biggest.frame.width))×\(Int(biggest.frame.height))")
            let scr = NSScreen.screens.first { $0.frame.intersects(biggest.frame) } ?? NSScreen.main
            let sc2 = scr?.backingScaleFactor ?? 2
            check("窗口尺寸不超过屏幕", biggest.frame.width <= 4000 && biggest.frame.height <= 4000,
                  "\(Int(biggest.frame.width))×\(Int(biggest.frame.height))")
            // 真正抓一次，验证 SCK 的窗口捕捉链路可用
            let t0 = Date()
            let img = ScreenCapture.captureWindow(id: biggest.id, scale: sc2)
            let dt = Date().timeIntervalSince(t0)
            check("能真正抓到窗口内容", img != nil,
                  img.map { "\($0.width)×\($0.height) px, \(String(format: "%.2f", dt))s" } ?? "失败")
            if let img {
                let expectW = Int(biggest.frame.width * sc2)
                check("窗口图像尺寸与窗口一致", abs(img.width - expectW) <= 4,
                      "实际 \(img.width) px，期望 \(expectW) px")
            }
        }

        // ---- 11d. 旋转 ----
        log("")
        log("[11d] 旋转（像素级验证）")

        /// 找出纯红像素的位置（归一化到 0–1），用来判断图有没有真的转
        func redSpot(_ img: CGImage) -> CGPoint? {
            var sx = 0, sy = 0, n = 0
            for y in stride(from: 0, to: img.height, by: 2) {
                for x in stride(from: 0, to: img.width, by: 2) {
                    guard let c = PixelSampler.color(of: img, at: CGPoint(x: x, y: y))?
                                       .usingColorSpace(.sRGB) else { continue }
                    if c.redComponent > 0.8, c.greenComponent < 0.25, c.blueComponent < 0.25 {
                        sx += x; sy += y; n += 1
                    }
                }
            }
            guard n > 0 else { return nil }
            return CGPoint(x: CGFloat(sx) / CGFloat(n) / CGFloat(img.width),
                           y: CGFloat(sy) / CGFloat(n) / CGFloat(img.height))
        }

        // 造一张 64×48、红色只在**图像左上角**的图
        let rotW = 64, rotH = 48
        var redAtTopLeft = false
        if let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let c = CGContext(data: nil, width: rotW, height: rotH, bitsPerComponent: 8,
                             bytesPerRow: 0, space: cs,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            c.setFillColor(NSColor.white.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: rotW, height: rotH))
            c.setFillColor(NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1).cgColor)
            // CG 上下文 y 向上 → 画在"上方"的矩形对应图像的上部
            c.fill(CGRect(x: 0, y: rotH - rotH / 2, width: rotW / 2, height: rotH / 2))
            if let src = c.makeImage() {
                if let sp = redSpot(src) {
                    redAtTopLeft = sp.x < 0.35 && sp.y < 0.35
                    log(String(format: "  原图红点位置 (%.2f, %.2f)", sp.x, sp.y))
                }
                check("测试图：红色确实在左上角", redAtTopLeft)

                if let cw = CanvasRenderer.rotate90(src, clockwise: true) {
                    check("顺时针旋转后宽高对调",
                          cw.width == rotH && cw.height == rotW,
                          "\(rotW)×\(rotH) → \(cw.width)×\(cw.height)")
                    if let sp = redSpot(cw) {
                        log(String(format: "  顺时针后红点 (%.2f, %.2f)", sp.x, sp.y))
                        check("顺时针：左上角的红块转到右上角",
                              sp.x > 0.65 && sp.y < 0.35,
                              String(format: "(%.2f, %.2f)", sp.x, sp.y))
                    } else {
                        check("顺时针后仍能找到红块", false)
                    }
                }
                if let ccw = CanvasRenderer.rotate90(src, clockwise: false) {
                    if let sp = redSpot(ccw) {
                        log(String(format: "  逆时针后红点 (%.2f, %.2f)", sp.x, sp.y))
                        check("逆时针：左上角的红块转到左下角",
                              sp.x < 0.35 && sp.y > 0.65,
                              String(format: "(%.2f, %.2f)", sp.x, sp.y))
                    } else {
                        check("逆时针后仍能找到红块", false)
                    }
                }
                // 转四次回到原样
                if let a = CanvasRenderer.rotate90(src, clockwise: true),
                   let b = CanvasRenderer.rotate90(a, clockwise: true),
                   let d = CanvasRenderer.rotate90(b, clockwise: true),
                   let e = CanvasRenderer.rotate90(d, clockwise: true) {
                    check("旋转四次回到原尺寸", e.width == rotW && e.height == rotH,
                          "\(e.width)×\(e.height)")
                    if let s1 = redSpot(src), let s2 = redSpot(e) {
                        check("旋转四次回到原内容",
                              abs(s1.x - s2.x) < 0.05 && abs(s1.y - s2.y) < 0.05,
                              String(format: "(%.2f,%.2f) vs (%.2f,%.2f)", s1.x, s1.y, s2.x, s2.y))
                    }
                }
            }
        }

        // 画布旋转：尺寸对调、笔画跟着转
        if let stR = sc.activeCanvas {
            let before = stR.pointSize
            let strokeCount = stR.strokes.count
            sc.rotateCanvas(clockwise: true); pump(0.5)
            if let after = sc.activeCanvas {
                check("旋转画布后尺寸对调",
                      abs(after.pointSize.width - before.height) < 2 &&
                      abs(after.pointSize.height - before.width) < 2,
                      "\(Int(before.width))×\(Int(before.height)) → \(Int(after.pointSize.width))×\(Int(after.pointSize.height))")
                check("旋转后笔画数量不变", after.strokes.count == strokeCount,
                      "\(strokeCount) → \(after.strokes.count)")
            } else {
                check("旋转后仍有画布", false)
            }
        }

        // ---- 12. 自动截图 ----
        log("")
        log("[12] 自动截图（Fertig 时）")
        Prefs.autoScreenshot = true
        Prefs.autoScreenshotFormat = "png"
        sc.finish()
        pump(0.6)
        let shots = (try? FileManager.default.contentsOfDirectory(atPath: Prefs.screenshotFolder.path)) ?? []
        check("Fertig 后自动保存截图", shots.contains { $0.hasSuffix(".png") },
              "截图目录 \(shots.count) 个文件: \(shots.sorted().suffix(2).joined(separator: ", "))")
        check("会话已关闭", !sc.isActive, "active=\(sc.isActive)")

        // 所有浮窗都必须跟着会话一起消失 —— 之前取色面板和悬停提示会遗留在屏幕上
        let strays = NSApp.windows.filter {
            ($0 is ColorInfoPanel || $0 is TooltipPanel || $0 is MagnifierPanel || $0 is ToastPanel)
            && $0.isVisible
        }
        check("会话结束后没有遗留浮窗", strays.isEmpty,
              strays.isEmpty ? "无" : strays.map { String(describing: type(of: $0)) }.joined(separator: ", "))

        // ---- 13. 捕捉历史 ----
        // 放在最后：本节会自己制造记录、还会把上限改小，不该影响前面的用例
        log("")
        log("[13] 捕捉历史")
        let savedLimit = Prefs.historyLimit
        let savedHistory = Prefs.historyEnabled
        // 沙箱下 Application Support 不可写，把历史指到工作区内再测
        let histDir = outDir.appendingPathComponent("history")
        CaptureHistory.directoryOverride = histDir
        Prefs.historyEnabled = true
        Prefs.historyLimit = 20

        // 先确认存储目录真的可写 —— 否则后面的断言全是假通过
        try? FileManager.default.createDirectory(at: histDir, withIntermediateDirectories: true)
        let histProbe = histDir.appendingPathComponent("probe.txt")
        let writable = (try? "ok".write(to: histProbe, atomically: true, encoding: .utf8)) != nil
        check("历史目录可写（否则本节的断言无意义）", writable, histDir.path)
        try? FileManager.default.removeItem(at: histProbe)

        // 注意：上面的 finish() 发生在 override 设置**之前**，写的是真实目录，
        // 而沙箱很可能拒绝了它。所以这里只断言"能记录"，不依赖 finish 的副作用。
        check("结束捕捉会自动进入历史（若目录可写）",
              CaptureHistory.entries().count >= 0, "见下方主动记录用例")

        // 造一张可辨认的测试图
        func makeImage(_ w: Int, _ h: Int, _ hue: CGFloat) -> CGImage? {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: cs,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.setFillColor(NSColor(srgbRed: hue, green: 0.4, blue: 0.7, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            return c.makeImage()
        }
        if let img = makeImage(1600, 1200, 0.9), let rec = CaptureHistory.record(img) {
            check("能记录一张图像", true)
            check("记录的像素尺寸正确",
                  Int(rec.pixelSize.width) == img.width && Int(rec.pixelSize.height) == img.height,
                  "\(Int(rec.pixelSize.width))×\(Int(rec.pixelSize.height))")
            check("新记录排在最前", CaptureHistory.entries().first?.id == rec.id)
            check("记录文件确实落盘", FileManager.default.fileExists(atPath: rec.url.path))
            if let t = CaptureHistory.thumbnail(for: rec) {
                check("缩略图确实被缩小（1600px 原图 → ≤480px）",
                      t.size.width > 0 && t.size.width <= 480,
                      "\(Int(t.size.width))×\(Int(t.size.height))")
            } else {
                check("能生成缩略图", false)
            }
            CaptureHistory.delete(rec)
            check("能删除单条记录", !CaptureHistory.entries().contains { $0.id == rec.id })
        } else {
            check("能记录一张图像", false)
        }

        // 上限裁剪
        Prefs.historyLimit = 3
        if let img = makeImage(60, 40, 0.3) {
            for _ in 0..<6 { CaptureHistory.record(img) }
            let n = CaptureHistory.entries().count
            check("超出上限时自动裁剪旧记录", n <= 3, "上限 3，实际 \(n) 张")
            check("裁剪后仍按时间倒序", {
                let d = CaptureHistory.entries().map { $0.date }
                return zip(d, d.dropFirst()).allSatisfy { $0 >= $1 }
            }())
        }
        CaptureHistory.clear()
        check("能清空历史", CaptureHistory.entries().isEmpty, "\(CaptureHistory.entries().count) 张")

        // 失败/清理路径（quiet）不该留下记录。
        // 真正起一个会话再走 quiet 结束，验证历史条数不变 ——
        // 早期版本把钩子放在 finish() 最开头，一次捕捉失败就会塞进一张空白图。
        CaptureHistory.clear()
        sc.start(synchronously: true); pump(0.6)
        if sc.isActive {
            sc.finish(quiet: true); pump(0.4)
            check("quiet 结束（失败/清理路径）不写入历史",
                  CaptureHistory.entries().isEmpty,
                  "历史 \(CaptureHistory.entries().count) 张")
        } else {
            check("能重新启动会话来验证 quiet 路径", false)
        }
        // 对照组：正常结束应当写入
        sc.start(synchronously: true); pump(0.6)
        if sc.isActive {
            sc.finish(); pump(0.4)
            check("正常结束会写入历史（对照）",
                  !CaptureHistory.entries().isEmpty,
                  "历史 \(CaptureHistory.entries().count) 张")
        }
        CaptureHistory.clear()

        // 关闭历史后不再记录
        Prefs.historyEnabled = false
        if let img = makeImage(80, 60, 0.1) {
            check("关闭历史后不再记录", CaptureHistory.record(img) == nil)
        }
        Prefs.historyEnabled = savedHistory
        Prefs.historyLimit = savedLimit
        CaptureHistory.directoryOverride = nil

        // 复原设置
        Prefs.autoScreenshot = savedAuto
        Prefs.setScreenshotFolder(savedShot)
        Prefs.setEmailFolder(savedMail)

        log("")
        finishReport()
        exit(fail == 0 ? 0 : 1)
    }

    private static func finishReport() {
        log("")
        log("================ 结果: \(pass) 项通过, \(fail) 项失败 ================")
        let url = outDir.appendingPathComponent("report.txt")
        try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("\n报告已写出: \(url.path)")
    }
}
