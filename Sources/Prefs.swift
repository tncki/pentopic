// Prefs.swift — 偏好设置（对应原版“Einstellungen”对话框）
import AppKit

enum CursorMode: Int { case normal = 0, toolSymbol = 1 }
enum ScreenMode: Int { case mouse = 0, first = 1, second = 2 }

enum Prefs {

    private static let d = UserDefaults.standard

    private enum K {
        static let cursorMode = "cursorMode"
        static let wheelZoom = "wheelZoom"
        static let autoOpen = "autoOpen"
        static let quitOnFinish = "quitOnFinish"
        static let autoScreenshot = "autoScreenshot"
        static let autoScreenshotFormat = "autoScreenshotFormat"
        static let screenMode = "screenMode"
        static let screenshotFolder = "screenshotFolder"
        static let emailFolder = "emailFolder"
        static let buttonW = "buttonW"
        static let buttonH = "buttonH"
        static let extraColors = "extraColors"
        static let language = "language"
        static let hotKeyCode = "hotKeyCode"
        static let lastTool = "lastTool"
        static let lastSwatch = "lastSwatch"
        static let lastPenSize = "lastPenSize"
        static let toolbarX = "toolbarX"
        static let toolbarY = "toolbarY"
        static let startBtnX = "startBtnX"
        static let startBtnY = "startBtnY"
    }

    static func registerDefaults() {
        d.register(defaults: [
            K.cursorMode: CursorMode.normal.rawValue,
            K.wheelZoom: true,
            K.autoOpen: false,
            K.quitOnFinish: false,
            K.autoScreenshot: false,
            K.autoScreenshotFormat: "png",
            K.screenMode: ScreenMode.mouse.rawValue,
            K.buttonW: 30,
            K.buttonH: 30,
            K.extraColors: [String](),
            K.language: "auto",
            K.hotKeyCode: 101,          // F9
            K.lastTool: ToolKind.pen.rawValue,
            K.lastSwatch: 0,
            K.lastPenSize: 1
        ])
    }

    // MARK: 行为

    static var cursorMode: CursorMode {
        get { CursorMode(rawValue: d.integer(forKey: K.cursorMode)) ?? .normal }
        set { d.set(newValue.rawValue, forKey: K.cursorMode) }
    }
    static var wheelZoom: Bool {
        get { d.bool(forKey: K.wheelZoom) }
        set { d.set(newValue, forKey: K.wheelZoom) }
    }
    static var autoOpen: Bool {
        get { d.bool(forKey: K.autoOpen) }
        set { d.set(newValue, forKey: K.autoOpen) }
    }
    static var quitOnFinish: Bool {
        get { d.bool(forKey: K.quitOnFinish) }
        set { d.set(newValue, forKey: K.quitOnFinish) }
    }
    static var autoScreenshot: Bool {
        get { d.bool(forKey: K.autoScreenshot) }
        set { d.set(newValue, forKey: K.autoScreenshot) }
    }
    static var autoScreenshotFormat: String {
        get { d.string(forKey: K.autoScreenshotFormat) ?? "png" }
        set { d.set(newValue, forKey: K.autoScreenshotFormat) }
    }
    static var screenMode: ScreenMode {
        get { ScreenMode(rawValue: d.integer(forKey: K.screenMode)) ?? .mouse }
        set { d.set(newValue.rawValue, forKey: K.screenMode) }
    }

    // MARK: 目录

    static var screenshotFolder: URL {
        if let s = d.string(forKey: K.screenshotFolder), !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Pointofix/Screenshots")
    }
    static func setScreenshotFolder(_ u: URL) { d.set(u.path, forKey: K.screenshotFolder) }

    static var emailFolder: URL {
        if let s = d.string(forKey: K.emailFolder), !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Pointofix/Email")
    }
    static func setEmailFolder(_ u: URL) { d.set(u.path, forKey: K.emailFolder) }

    // MARK: 工具栏尺寸

    static var buttonW: CGFloat {
        get { max(22, CGFloat(d.integer(forKey: K.buttonW))) }
        set { d.set(Int(newValue), forKey: K.buttonW) }
    }
    static var buttonH: CGFloat {
        get { max(22, CGFloat(d.integer(forKey: K.buttonH))) }
        set { d.set(Int(newValue), forKey: K.buttonH) }
    }

    // MARK: 附加颜色

    static var extraColors: [String] {
        get { d.stringArray(forKey: K.extraColors) ?? [] }
        set { d.set(Array(newValue.prefix(10)), forKey: K.extraColors) }
    }

    // MARK: 语言

    static var language: AppLang? {
        get {
            guard let raw = d.string(forKey: K.language), raw != "auto" else { return nil }
            // 兼容早期版本存的 "zh"（当时只有简体）
            if raw == "zh" { return .zh }
            return AppLang(rawValue: raw)
        }
        set { d.set(newValue?.rawValue ?? "auto", forKey: K.language) }
    }

    static func resolveLanguage() -> AppLang {
        if let l = language { return l }
        for p in Locale.preferredLanguages {
            let s = p.lowercased()
            if s.hasPrefix("de") { return .de }
            if s.hasPrefix("en") { return .en }
            if s.hasPrefix("zh") {
                // zh-Hant-TW / zh-Hant-HK / zh-TW / zh-HK / zh-MO → 繁體
                if s.contains("hant") || s.hasSuffix("-tw") || s.contains("-tw-")
                    || s.contains("-hk") || s.contains("-mo") { return .zhHant }
                return .zh    // zh-Hans-CN / zh-CN / zh-SG → 简体
            }
        }
        return .en
    }

    // MARK: 热键

    static var hotKeyCode: Int {
        get { d.integer(forKey: K.hotKeyCode) }
        set { d.set(newValue, forKey: K.hotKeyCode) }
    }

    // MARK: 会话记忆

    static var lastTool: ToolKind {
        get { ToolKind(rawValue: d.string(forKey: K.lastTool) ?? "") ?? .pen }
        set { d.set(newValue.rawValue, forKey: K.lastTool) }
    }
    static var lastSwatch: Int {
        get { min(max(0, d.integer(forKey: K.lastSwatch)), max(0, Palette.all.count - 1)) }
        set { d.set(newValue, forKey: K.lastSwatch) }
    }
    static var lastPenSize: Int {
        get { PenSize.clamp(d.integer(forKey: K.lastPenSize)) }
        set { d.set(PenSize.clamp(newValue), forKey: K.lastPenSize) }
    }

    // MARK: 窗口位置

    static func toolbarOrigin() -> NSPoint? {
        guard d.object(forKey: K.toolbarX) != nil else { return nil }
        return NSPoint(x: d.double(forKey: K.toolbarX), y: d.double(forKey: K.toolbarY))
    }
    static func setToolbarOrigin(_ p: NSPoint) {
        d.set(Double(p.x), forKey: K.toolbarX); d.set(Double(p.y), forKey: K.toolbarY)
    }
    static func startOrigin() -> NSPoint? {
        guard d.object(forKey: K.startBtnX) != nil else { return nil }
        return NSPoint(x: d.double(forKey: K.startBtnX), y: d.double(forKey: K.startBtnY))
    }
    static func setStartOrigin(_ p: NSPoint) {
        d.set(Double(p.x), forKey: K.startBtnX); d.set(Double(p.y), forKey: K.startBtnY)
    }

    static func ensureFolders() {
        for u in [screenshotFolder, emailFolder] {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }
}
