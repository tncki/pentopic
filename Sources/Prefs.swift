// Prefs.swift — 偏好设置（对应原版“Einstellungen”对话框）
import AppKit
import Carbon.HIToolbox

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
        static let paletteHexes = "paletteHexes"
        static let numberShape = "numberShape"
        static let shapeSlots = "shapeSlots"
        static let filenameTemplate = "filenameTemplate"
        static let captureDelay = "captureDelay"
        static let historyEnabled = "historyEnabled"
        static let historyLimit = "historyLimit"
        static let language = "language"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
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
            K.lastPenSize: 1,
            K.filenameTemplate: "{app}-{date}-{time}",
            K.captureDelay: 0,
            K.historyEnabled: true,
            K.historyLimit: 20
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

    /// 自动保存的文件名模板。占位符：{app} {date} {time} {n}
    static var filenameTemplate: String {
        get { d.string(forKey: K.filenameTemplate) ?? "{app}-{date}-{time}" }
        set { d.set(newValue, forKey: K.filenameTemplate) }
    }

    /// 捕捉延时（秒）。0 = 立即捕捉；用来截「打开的下拉菜单」这类界面。
    static var captureDelay: Int {
        get { max(0, min(30, d.integer(forKey: K.captureDelay))) }
        set { d.set(newValue, forKey: K.captureDelay) }
    }

    /// 是否把每次结束的捕捉存进历史
    static var historyEnabled: Bool {
        get { d.object(forKey: K.historyEnabled) as? Bool ?? true }
        set { d.set(newValue, forKey: K.historyEnabled) }
    }

    /// 历史保留张数（超出后自动删除最旧的）
    static var historyLimit: Int {
        get { let v = d.integer(forKey: K.historyLimit); return v > 0 ? min(500, v) : 20 }
        set { d.set(max(1, min(500, newValue)), forKey: K.historyLimit) }
    }

    /// 用户右键改过的标准色槽位（空数组 = 全用默认色）
    static var paletteHexes: [String] {
        get { d.stringArray(forKey: K.paletteHexes) ?? [] }
        set { d.set(Array(newValue.prefix(Palette.slotCount)), forKey: K.paletteHexes) }
    }

    /// 序号标记形状
    static var numberShape: NumberShape {
        get { NumberShape(rawValue: d.string(forKey: K.numberShape) ?? "") ?? .circle }
        set { d.set(newValue.rawValue, forKey: K.numberShape) }
    }

    /// 形状槽位分配（7 个槽位，存 ToolKind 的 rawValue）。空 = 默认布局。
    static var shapeSlots: [String] {
        get { d.stringArray(forKey: K.shapeSlots) ?? [] }
        set { d.set(newValue, forKey: K.shapeSlots) }
    }

    /// 可被右键替换的形状工具及其默认排布
    static let shapeCatalog: [ToolKind] = [.line, .arrow, .doubleArrow,
                                           .rect, .rectFilled, .ellipse, .ellipseFilled]
    static var defaultShapeSlots: [String] { shapeCatalog.map { $0.rawValue } }

    /// 当前生效的形状槽位（长度与 shapeCatalog 一致）
    static var effectiveShapeSlots: [ToolKind] {
        let stored = shapeSlots
        guard stored.count == shapeCatalog.count else { return shapeCatalog }
        let parsed = stored.compactMap { ToolKind(rawValue: $0) }
        return parsed.count == shapeCatalog.count ? parsed : shapeCatalog
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

    /// 全局热键。早期版本只存了 keyCode（-1/-2 是 ⌥⌘P / ⌃⌥P 的占位值），
    /// 这里做一次性迁移，老用户的设置不会丢。
    static var hotKeySpec: HotKeySpec {
        get {
            let code = d.integer(forKey: K.hotKeyCode)
            guard d.object(forKey: K.hotKeyModifiers) != nil else {
                switch code {
                case -1: return HotKeySpec(keyCode: UInt32(kVK_ANSI_P),
                                           modifiers: UInt32(cmdKey | optionKey))
                case -2: return HotKeySpec(keyCode: UInt32(kVK_ANSI_P),
                                           modifiers: UInt32(controlKey | optionKey))
                case 0:  return .default
                default: return HotKeySpec(keyCode: UInt32(max(0, code)), modifiers: 0)
                }
            }
            return HotKeySpec(keyCode: UInt32(max(0, code)),
                              modifiers: UInt32(max(0, d.integer(forKey: K.hotKeyModifiers))))
        }
        set {
            d.set(Int(newValue.keyCode), forKey: K.hotKeyCode)
            d.set(Int(newValue.modifiers), forKey: K.hotKeyModifiers)
        }
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

    /// 恢复默认布局：调色板、形状槽位、序号形状、附加颜色全部还原
    static func resetLayout() {
        d.removeObject(forKey: K.paletteHexes)
        d.removeObject(forKey: K.shapeSlots)
        d.removeObject(forKey: K.numberShape)
        d.removeObject(forKey: K.extraColors)
        d.removeObject(forKey: K.lastSwatch)
        d.removeObject(forKey: K.lastTool)
        d.removeObject(forKey: K.lastPenSize)
    }

    // MARK: 配置导出 / 导入

    /// 可保存的界面配置项
    static var layoutSnapshot: [String: Any] {
        ["paletteHexes": paletteHexes,
         "shapeSlots": shapeSlots,
         "numberShape": numberShape.rawValue,
         "extraColors": extraColors,
         "penSize": lastPenSize,
         "swatch": lastSwatch,
         "tool": lastTool.rawValue]
    }

    static func applyLayout(_ dict: [String: Any]) {
        if let v = dict["paletteHexes"] as? [String] { paletteHexes = v }
        if let v = dict["shapeSlots"] as? [String] { shapeSlots = v }
        if let v = dict["numberShape"] as? String, let n = NumberShape(rawValue: v) { numberShape = n }
        if let v = dict["extraColors"] as? [String] { extraColors = v }
        if let v = dict["penSize"] as? Int { lastPenSize = v }
        if let v = dict["swatch"] as? Int { lastSwatch = v }
        if let v = dict["tool"] as? String, let t = ToolKind(rawValue: v) { lastTool = t }
    }

    static func ensureFolders() {
        for u in [screenshotFolder, emailFolder] {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }
}
