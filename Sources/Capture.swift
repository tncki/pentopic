// Capture.swift — 屏幕冻结（截屏）
import AppKit
import ScreenCaptureKit

struct CapturedScreen {
    let displayID: CGDirectDisplayID
    let cgImage: CGImage
    /// 点为单位、与 NSScreen.frame 一致的逻辑尺寸
    let pointSize: CGSize
    let scale: CGFloat
}

enum ScreenCapture {

    /// 开发/自检用：POFIX_FAKE_CAPTURE=1 时使用合成画面，跳过权限检查
    static var fakeCapture: Bool {
        ProcessInfo.processInfo.environment["POFIX_FAKE_CAPTURE"] == "1"
    }

    static var hasPermission: Bool {
        if fakeCapture { return true }
        return CGPreflightScreenCaptureAccess()
    }

    /// ⚠️ 授权引导里**故意不调用**这个方法。
    /// 它在 macOS 15+ 上是非阻塞的：弹出系统自带的授权框后立刻返回 false，
    /// 结果系统弹窗和自定义引导弹窗会同时出现（用户看到两个框）。
    /// 保留它仅供将来需要"强制让系统登记本应用"的场景使用。
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 同步抓取一块屏幕。会排除本程序自身的窗口，保证冻结画面干净。
    static func capture(screen: NSScreen) -> CapturedScreen? {
        let id = displayID(of: screen)
        let scale = screen.backingScaleFactor
        let pointSize = screen.frame.size

        if fakeCapture, let cg = synthetic(pointSize: pointSize, scale: scale) {
            return CapturedScreen(displayID: id, cgImage: cg, pointSize: pointSize, scale: scale)
        }

        if let cg = captureViaScreenCaptureKit(displayID: id, pointSize: pointSize, scale: scale) {
            return CapturedScreen(displayID: id, cgImage: cg, pointSize: pointSize, scale: scale)
        }
        // 回退：CGDisplayCreateImage（已废弃但可用）
        if let cg = CGDisplayCreateImage(id) {
            return CapturedScreen(displayID: id, cgImage: cg, pointSize: pointSize, scale: scale)
        }
        return nil
    }

    private static func captureViaScreenCaptureKit(displayID: CGDirectDisplayID,
                                                   pointSize: CGSize,
                                                   scale: CGFloat) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        let sem = DispatchSemaphore(value: 0)
        let box = Box<CGImage>()

        Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                 onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    sem.signal(); return
                }
                let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display,
                                             excludingApplications: mine,
                                             exceptingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.width = Int((pointSize.width * scale).rounded())
                cfg.height = Int((pointSize.height * scale).rounded())
                cfg.showsCursor = Prefs.captureCursor
                cfg.captureResolution = .best
                cfg.scalesToFit = false
                cfg.ignoreShadowsDisplay = true
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                     configuration: cfg)
                box.set(img)
            } catch {
                box.set(nil)
            }
            sem.signal()
        }

        _ = sem.wait(timeout: .now() + 10)
        return box.get()
    }

    static func nsImage(from c: CapturedScreen) -> NSImage {
        NSImage(cgImage: c.cgImage, size: c.pointSize)
    }
}


/// 跨并发域传递结果的容器。
///
/// 这些函数是"同步外壳 + 异步内核"：用信号量等 `Task.detached` 的结果。
/// 直接在 `Task` 里改外层的 `var`，在 Swift 6 的严格并发检查下是**编译错误**；
/// 本地 Command Line Tools 默认仍是 Swift 5 语言模式，只给警告 ——
/// 所以这个问题直到 GitHub Actions（Swift 6）上才暴露，本地一直是"过"的。
///
/// `@unchecked Sendable` 是有意的：读写都由内部锁保护，不需要编译器再插一层。
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    init() {}
    func set(_ v: T?) { lock.lock(); value = v; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - 窗口捕捉

struct WindowInfo {
    let id: CGWindowID
    let title: String
    let app: String
    /// Cocoa 屏幕坐标（原点在左下）
    let frame: CGRect
}

extension ScreenCapture {

    /// 列出当前屏幕上可捕捉的窗口（已按面积从大到小排序，过滤掉过小的辅助窗口）
    static func windows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // Quartz 的窗口坐标原点在**主屏左上**，要转成 Cocoa 的左下原点
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let myPID = ProcessInfo.processInfo.processIdentifier

        var out: [WindowInfo] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPID else { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let q = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard q.width >= 80, q.height >= 60 else { continue }
            let app = (w[kCGWindowOwnerName as String] as? String) ?? "?"
            let rawTitle = (w[kCGWindowName as String] as? String) ?? ""
            let title = rawTitle.isEmpty ? app : rawTitle
            let cocoa = CGRect(x: q.minX, y: primaryHeight - q.maxY,
                               width: q.width, height: q.height)
            out.append(WindowInfo(id: w[kCGWindowNumber as String] as? CGWindowID ?? 0,
                                  title: title, app: app, frame: cocoa))
        }
        return out.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
    }

    /// 抓取指定窗口（排除窗口阴影，否则画布会比窗口本身大一圈）
    static func captureWindow(id: CGWindowID, scale: CGFloat) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        let sem = DispatchSemaphore(value: 0)
        let box = Box<CGImage>()
        Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                 onScreenWindowsOnly: true)
                guard let win = content.windows.first(where: { $0.windowID == id }) else {
                    sem.signal(); return
                }
                let filter = SCContentFilter(desktopIndependentWindow: win)
                let cfg = SCStreamConfiguration()
                cfg.width = Int((win.frame.width * scale).rounded())
                cfg.height = Int((win.frame.height * scale).rounded())
                cfg.showsCursor = false
                cfg.ignoreShadowsSingleWindow = true
                cfg.captureResolution = .best
                box.set(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg))
            } catch { box.set(nil) }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return box.get()
    }
}

// MARK: - 自检用合成画面

extension ScreenCapture {
    static func synthetic(pointSize: CGSize, scale: CGFloat) -> CGImage? {
        let pw = Int(pointSize.width * scale), ph = Int(pointSize.height * scale)
        guard pw > 0, ph > 0 else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: pointSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: pointSize))
        ctx.setFillColor(NSColor(srgbRed: 0.20, green: 0.30, blue: 0.55, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pointSize.width, height: 34))
        ctx.setFillColor(NSColor(srgbRed: 0.35, green: 0.62, blue: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 40, y: 90, width: 320, height: 180))

        // 加一些"真实内容"，否则纯色区域上的模糊/马赛克看不出任何变化，
        // 自检和演示图都会失去意义
        ShapeRenderer.drawText(ctx, "FROZEN SCREEN (synthetic)",
                               origin: CGPoint(x: 24, y: 44), fontSize: 26, color: .black)
        ShapeRenderer.drawText(ctx, """
        Account:  user@example.com
        Password:  hunter2-Secret-2026
        Token:     9f3c-a17b-4e02-bd55
        """, origin: CGPoint(x: 420, y: 120), fontSize: 20,
             color: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.2, alpha: 1))
        ShapeRenderer.drawText(ctx, """
        Pointofix works together with nearly every Windows application.
        Your presentations become more impressive and are absorbed
        better by the audience.
        """, origin: CGPoint(x: 40, y: 340), fontSize: 17,
             color: NSColor(srgbRed: 0.25, green: 0.25, blue: 0.3, alpha: 1))
        return ctx.makeImage()
    }
}
