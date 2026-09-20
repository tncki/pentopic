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
        var out: CGImage?

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
                cfg.showsCursor = false
                cfg.captureResolution = .best
                cfg.scalesToFit = false
                cfg.ignoreShadowsDisplay = true
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                     configuration: cfg)
                out = img
            } catch {
                out = nil
            }
            sem.signal()
        }

        _ = sem.wait(timeout: .now() + 10)
        return out
    }

    static func nsImage(from c: CapturedScreen) -> NSImage {
        NSImage(cgImage: c.cgImage, size: c.pointSize)
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
        ShapeRenderer.drawText(ctx, "FROZEN SCREEN (synthetic)",
                               origin: CGPoint(x: 24, y: 44), fontSize: 28, color: .black)
        return ctx.makeImage()
    }
}
