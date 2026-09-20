// Core.swift — 本地化 / 偏好设置 / 绘图模型 / 标注图层
import AppKit
import CoreText

// MARK: - 本地化（德/英/中，原版为德英）

enum AppLang: String, CaseIterable {
    case en
    case zh     = "zh-Hans"
    case zhHant = "zh-Hant"
    case de

    var label: String {
        switch self {
        case .en: return "English"
        case .zh: return "简体中文"
        case .zhHant: return "繁體中文"
        case .de: return "Deutsch"
        }
    }

    /// 设置里语言选择器的顺序
    static var selectable: [AppLang] { [.en, .zh, .zhHant, .de] }
}

enum L {
    static var lang: AppLang = .en

    /// 四语本地化。简繁必须分别书写 —— 台湾/香港用词与大陆差异很大
    /// （设置→設定、软件→軟體、屏幕→螢幕、打印→列印、剪贴板→剪貼簿 …），
    /// 不是简单的字形转换，所以不做运行时转码。
    /// 参数顺序沿用历史的 (德, 英, 简, 繁) 以兼容全部调用点。
    static func s(_ de: String, _ en: String, _ zh: String, _ zhHant: String) -> String {
        switch lang {
        case .de:     return de
        case .en:     return en
        case .zh:     return zh
        case .zhHant: return zhHant
        }
    }
}
func LS(_ de: String, _ en: String, _ zh: String, _ zhHant: String) -> String { L.s(de, en, zh, zhHant) }

// MARK: - 品牌信息（改名只需改 release.conf，不用动代码）

enum Brand {
    /// 显示名，来自 Info.plist 的 CFBundleDisplayName
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Pointofix"
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    /// 版权声明，取自 Info.plist（由 app.conf 的 COPYRIGHT 生成），保证与打包信息一致
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    /// 被致敬的原作（署名必须保留，但表述为"受其启发的独立实现"）
    static let upstreamName = "Pointofix"
    static let upstreamAuthor = "Thomas Gottfried EDV"
    static let upstreamURL = "https://www.pointofix.de/"
}

// MARK: - 工具

enum ToolKind: String, CaseIterable {
    case pen, eraser
    case line, arrow, doubleArrow
    case rect, rectFilled, ellipse, ellipseFilled
    case text, check, cross
    case number            // 序号标注（自动递增）
    case spotlight         // 聚焦高亮：其余部分压暗
    case blur, pixelate    // 打码：模糊 / 像素化
    case eyedropper        // 屏幕取色
    case region, magnifier
    case zoomIn, zoomOut

    var symbol: String {
        switch self {
        case .pen: return "pencil"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .doubleArrow: return "arrow.left.and.right"
        case .rect: return "rectangle"
        case .rectFilled: return "rectangle.fill"
        case .ellipse: return "circle"
        case .ellipseFilled: return "circle.fill"
        case .text: return "textformat"
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .number: return "1.circle"
        case .spotlight: return "flashlight.on.fill"
        case .blur: return "drop.fill"
        case .pixelate: return "squareshape.split.3x3"
        case .eyedropper: return "eyedropper"
        case .region: return "rectangle.dashed"
        case .magnifier: return "magnifyingglass"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .pen: return LS("Freihand-Stift", "Freehand pen", "自由画笔", "自由筆刷")
        case .eraser: return LS("Radiergummi", "Eraser", "橡皮擦", "橡皮擦")
        case .line: return LS("Linie", "Line", "直线", "直線")
        case .arrow: return LS("Pfeil", "Arrow", "箭头", "箭頭")
        case .doubleArrow: return LS("Doppelpfeil", "Double arrow", "双向箭头", "雙向箭頭")
        case .rect: return LS("Rechteck", "Rectangle", "矩形", "矩形")
        case .rectFilled: return LS("Gefülltes Rechteck", "Filled rectangle", "实心矩形", "實心矩形")
        case .ellipse: return LS("Ellipse", "Ellipse", "椭圆", "橢圓")
        case .ellipseFilled: return LS("Gefüllte Ellipse", "Filled ellipse", "实心椭圆", "實心橢圓")
        case .text: return LS("Texteingabe", "Text", "文字", "文字")
        case .check: return LS("Häkchen", "Check mark", "对勾", "打勾")
        case .cross: return LS("Kreuz", "Cross", "叉号", "叉號")
        case .number: return LS("Nummerierung", "Step number", "序号标注", "序號標註")
        case .spotlight: return LS("Fokus", "Spotlight", "聚焦高亮", "聚焦高亮")
        case .blur: return LS("Weichzeichnen", "Blur", "模糊打码", "模糊打碼")
        case .pixelate: return LS("Verpixeln", "Pixelate", "马赛克打码", "馬賽克打碼")
        case .eyedropper: return LS("Farbpipette", "Colour picker", "颜色吸管", "顏色吸管")
        case .region: return LS("Bildbereich wählen", "Select region", "选区", "選取範圍")
        case .magnifier: return LS("Lupe", "Magnifier", "放大镜", "放大鏡")
        case .zoomIn: return LS("Hineinzoomen", "Zoom in", "放大视图", "放大檢視")
        case .zoomOut: return LS("Herauszoomen", "Zoom out", "缩小视图", "縮小檢視")
        }
    }

    /// 提示里的快捷键说明
    var shortcutHint: String {
        switch self {
        case .pen: return "B"
        case .eraser: return "E"
        case .line: return "G"
        case .arrow: return "P"
        case .doubleArrow: return "D"
        case .rect: return "R"
        case .rectFilled: return "⇧R"
        case .ellipse: return "O"
        case .ellipseFilled: return "⇧O"
        case .text: return "T"
        case .check: return "H"
        case .cross: return "K"
        case .number: return "N"
        case .spotlight: return "S"
        case .blur: return "U"
        case .pixelate: return "I"
        case .eyedropper: return "C"
        case .region: return "F"
        case .magnifier: return "M"
        case .zoomIn: return "+"
        case .zoomOut: return "−"
        }
    }

    /// 缩放视图下是否仍然可用。
    /// 原版在缩放视图里禁用绘图；放大镜是查看工具，理应可用（也方便逐像素取色）。
    var worksWhileZoomed: Bool {
        switch self {
        case .magnifier, .eyedropper, .zoomIn, .zoomOut: return true
        default: return false
        }
    }
}

// MARK: - 调色板

struct Swatch {
    var base: NSColor
    var alpha: CGFloat
    var isOpaque: Bool { alpha >= 0.999 }
    var color: NSColor { base.withAlphaComponent(alpha) }
}

enum Palette {
    static let markerAlpha: CGFloat = 0.35

    static let red = NSColor(srgbRed: 0.90, green: 0.11, blue: 0.14, alpha: 1)
    static let yellow = NSColor(srgbRed: 1.00, green: 0.84, blue: 0.00, alpha: 1)
    static let green = NSColor(srgbRed: 0.20, green: 0.74, blue: 0.20, alpha: 1)
    static let blue = NSColor(srgbRed: 0.16, green: 0.35, blue: 0.90, alpha: 1)
    static let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    static let checkGreen = NSColor(srgbRed: 0.09, green: 0.63, blue: 0.13, alpha: 1)
    static let crossRed = NSColor(srgbRed: 0.85, green: 0.09, blue: 0.09, alpha: 1)

    /// 每个槽位的默认颜色与透明度。透明度是槽位的属性 ——
    /// 用户右键改颜色时只换色相，不改变它是"马克笔"还是"不透明色"。
    static let defaults: [(NSColor, CGFloat)] = [
        (red, markerAlpha), (red, 1),
        (yellow, markerAlpha), (yellow, 1),
        (green, markerAlpha), (green, 1),
        (blue, markerAlpha), (blue, 1),
        (white, 1), (black, 1)
    ]

    static let slotCount = defaults.count

    /// 原版标准色：4 个透明 + 4 个不透明，再加白、黑（左列透明，右列不透明）。
    /// 用户右键改过的槽位以 Prefs.paletteHexes 为准。
    static var standard: [Swatch] {
        let custom = Prefs.paletteHexes
        return defaults.enumerated().map { i, d in
            if i < custom.count, let c = NSColor(hex: custom[i]) {
                return Swatch(base: c, alpha: d.1)
            }
            return Swatch(base: d.0, alpha: d.1)
        }
    }

    struct Preset { let name: String; let hex: String }

    /// 右键换色时可选的预设色
    static let presets: [Preset] = [
        Preset(name: LS("Rot", "Red", "红色", "紅色"), hex: "#E61C24"),
        Preset(name: LS("Orange", "Orange", "橙色", "橙色"), hex: "#FF7A00"),
        Preset(name: LS("Gelb", "Yellow", "黄色", "黃色"), hex: "#FFD400"),
        Preset(name: LS("Grün", "Green", "绿色", "綠色"), hex: "#33BD33"),
        Preset(name: LS("Türkis", "Teal", "青色", "青色"), hex: "#00C2A8"),
        Preset(name: LS("Blau", "Blue", "蓝色", "藍色"), hex: "#2959E6"),
        Preset(name: LS("Violett", "Purple", "紫色", "紫色"), hex: "#8B45D6"),
        Preset(name: LS("Pink", "Pink", "粉色", "粉色"), hex: "#FF3D8B"),
        Preset(name: LS("Braun", "Brown", "棕色", "棕色"), hex: "#8B5A2B"),
        Preset(name: LS("Grau", "Grey", "灰色", "灰色"), hex: "#808080"),
        Preset(name: LS("Weiß", "White", "白色", "白色"), hex: "#FFFFFF"),
        Preset(name: LS("Schwarz", "Black", "黑色", "黑色"), hex: "#000000")
    ]

    /// 恢复某个槽位的默认颜色（传 nil 表示全部恢复）
    static func resetSlot(_ index: Int?) {
        var arr = Prefs.paletteHexes
        if arr.isEmpty { arr = defaults.map { $0.0.hexString } }
        if let i = index, i < arr.count { arr[i] = defaults[i].0.hexString }
        else { arr = defaults.map { $0.0.hexString } }
        Prefs.paletteHexes = arr
    }

    /// 设置某个槽位的颜色
    static func setSlot(_ index: Int, hex: String) {
        var arr = Prefs.paletteHexes
        if arr.isEmpty { arr = defaults.map { $0.0.hexString } }
        while arr.count < slotCount { arr.append(defaults[arr.count].0.hexString) }
        guard index < arr.count else { return }
        arr[index] = hex
        Prefs.paletteHexes = arr
    }

    /// 用户自定义的附加色（最多 10 个，均为不透明）
    static var extra: [Swatch] {
        Prefs.extraColors.compactMap { NSColor(hex: $0) }.map { Swatch(base: $0, alpha: 1) }
    }

    static var all: [Swatch] { standard + extra }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

// MARK: - 画笔粗细（原版工具栏为 2×2 四个圆点）

enum PenSize {
    static let values: [CGFloat] = [2, 5, 11, 22]
    static var count: Int { values.count }
    static func clamp(_ i: Int) -> Int { min(max(i, 0), values.count - 1) }
}

// MARK: - 图形 / 笔画

enum Shape {
    case freehand([CGPoint])
    case line(CGPoint, CGPoint)
    case arrow(CGPoint, CGPoint)
    case doubleArrow(CGPoint, CGPoint)
    case rect(CGRect)
    case rectFilled(CGRect)
    case ellipse(CGRect)
    case ellipseFilled(CGRect)
    case text(String, CGPoint, CGFloat)   // 文本、左上角、字号
    case check(CGPoint, CGFloat)          // 中心、尺寸
    case cross(CGPoint, CGFloat)
    case number(Int, CGPoint, CGFloat, NumberShape)   // 序号、中心、直径、标记形状
    case spotlight(CGRect)                // 聚焦区（其余压暗）
    case redact(CGRect, RedactStyle)      // 打码区（读取底图做滤镜）
}

/// 序号的标记形状
enum NumberShape: String, CaseIterable {
    case circle, square, triangle

    var title: String {
        switch self {
        case .circle:   return LS("Kreis", "Circle", "圆形", "圓形")
        case .square:   return LS("Quadrat", "Square", "正方形", "正方形")
        case .triangle: return LS("Gleichseitiges Dreieck", "Equilateral triangle", "等边三角形", "等邊三角形")
        }
    }
    var symbol: String {
        switch self {
        case .circle: return "circle"
        case .square: return "square"
        case .triangle: return "triangle"
        }
    }
}

/// 打码方式
enum RedactStyle: String {
    case blur, pixelate

    var title: String {
        switch self {
        case .blur: return LS("Weichzeichnen", "Blur", "模糊", "模糊")
        case .pixelate: return LS("Verpixeln", "Pixelate", "马赛克", "馬賽克")
        }
    }
}

struct Stroke {
    var shape: Shape
    var color: NSColor
    var width: CGFloat
    var isEraser: Bool = false
}

enum BackgroundKind: String, CaseIterable {
    case currentScreen, white, black, grid, dots, lines, clipboard
    var title: String {
        switch self {
        case .currentScreen: return LS("Aktueller Bildschirm", "Current screen", "当前屏幕", "當前螢幕")
        case .white: return LS("Weißes Blatt", "White sheet", "白色纸", "白色紙")
        case .black: return LS("Schwarzes Blatt", "Black sheet", "黑色纸", "黑色紙")
        case .grid: return LS("Kariert", "Squared", "方格纸", "方格紙")
        case .dots: return LS("Punktraster", "Dotted", "点阵纸", "點陣紙")
        case .lines: return LS("Linien", "Lined", "横线纸", "橫線紙")
        case .clipboard: return LS("Aus Zwischenablage einfügen", "Paste from clipboard", "从剪贴板粘贴", "從剪貼簿貼上")
        }
    }
    var symbol: String {
        switch self {
        case .currentScreen: return "display"
        case .white: return "doc"
        case .black: return "doc.fill"
        case .grid: return "squareshape.split.3x3"
        case .dots: return "circle.grid.3x3"
        case .lines: return "list.dash"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

// MARK: - 图形绘制

enum ShapeRenderer {

    static func draw(_ stroke: Stroke, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(1, stroke.width))
        if stroke.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
        } else {
            let c = stroke.color.usingColorSpace(.sRGB) ?? stroke.color
            ctx.setStrokeColor(c.cgColor)
            ctx.setFillColor(c.cgColor)
        }

        switch stroke.shape {
        case .freehand(let pts):
            if pts.count == 1, let p = pts.first {
                let w = max(1, stroke.width)
                ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            } else if pts.count > 1 {
                ctx.beginPath()
                ctx.move(to: pts[0])
                for p in pts.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
            }
        case .line(let a, let b):
            ctx.beginPath(); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        case .arrow(let a, let b):
            ctx.beginPath(); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            arrowHead(ctx, tip: b, from: a, width: stroke.width)
        case .doubleArrow(let a, let b):
            ctx.beginPath(); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            arrowHead(ctx, tip: b, from: a, width: stroke.width)
            arrowHead(ctx, tip: a, from: b, width: stroke.width)
        case .rect(let r):
            ctx.stroke(r)
        case .rectFilled(let r):
            ctx.fill(r)
        case .ellipse(let r):
            ctx.strokeEllipse(in: r)
        case .ellipseFilled(let r):
            ctx.fillEllipse(in: r)
        case .text(let s, let origin, let size):
            drawText(ctx, s, origin: origin, fontSize: size, color: stroke.color)
        case .check(let c, let s):
            drawCheck(ctx, center: c, size: s, width: stroke.width)
        case .cross(let c, let s):
            drawCross(ctx, center: c, size: s, width: stroke.width)
        case .number(let n, let c, let d, let ns):
            drawNumber(ctx, n, center: c, diameter: d, shape: ns, color: stroke.color)
        case .spotlight(let r):
            drawSpotlight(ctx, r)
        case .redact:
            // 真正的打码由 AnnotationLayer 处理（它拿得到底图）。
            // 走到这里只可能是实时预览，画个占位提示。
            if case .redact(let r, _) = stroke.shape {
                ctx.saveGState()
                ctx.setFillColor(NSColor(srgbRed: 0.35, green: 0.38, blue: 0.45, alpha: 0.55).cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(r)
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    private static func arrowHead(_ ctx: CGContext, tip: CGPoint, from: CGPoint, width: CGFloat) {
        let dx = tip.x - from.x, dy = tip.y - from.y
        let len = max(0.0001, sqrt(dx * dx + dy * dy))
        let ux = dx / len, uy = dy / len
        let head = max(10, width * 3.2)
        let spread: CGFloat = .pi / 7
        let cosA = cos(spread), sinA = sin(spread)
        let p1 = CGPoint(x: tip.x - head * (ux * cosA - uy * sinA), y: tip.y - head * (ux * sinA + uy * cosA))
        let p2 = CGPoint(x: tip.x - head * (ux * cosA + uy * sinA), y: tip.y - head * (-ux * sinA + uy * cosA))
        ctx.beginPath()
        ctx.move(to: p1); ctx.addLine(to: tip); ctx.addLine(to: p2)
        ctx.strokePath()
        // 实心箭头，视觉更接近原版
        ctx.beginPath()
        ctx.move(to: tip); ctx.addLine(to: p1); ctx.addLine(to: p2); ctx.closePath()
        ctx.fillPath()
    }

    /// y 轴向下的坐标系里用 CoreText 画多行文本
    static func drawText(_ ctx: CGContext, _ text: String, origin: CGPoint, fontSize: CGFloat, color: NSColor) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = fontSize * 1.28
        let c = color.usingColorSpace(.sRGB) ?? color
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
            let astr = NSAttributedString(string: line, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(astr)
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: origin.x, y: origin.y + lineHeight * CGFloat(i) + font.ascender)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(ctLine, ctx)
            ctx.restoreGState()
        }
    }

    static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = fontSize * 1.28
        let lines = text.components(separatedBy: "\n")
        var w: CGFloat = 0
        for line in lines {
            let s = (line as NSString).size(withAttributes: [.font: font])
            w = max(w, s.width)
        }
        return CGSize(width: max(w, fontSize), height: lineHeight * CGFloat(max(1, lines.count)))
    }

    /// 序号标记的轮廓路径（圆形 / 正方形 / 等边三角形，都内接于给定矩形）
    static func numberPath(_ shape: NumberShape, in r: CGRect) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: r, transform: nil)
        case .square:
            let radius = r.width * 0.14
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .triangle:
            // 等边三角形内接于该矩形的内切圆，重心即圆心
            let cx = r.midX, cy = r.midY, rad = min(r.width, r.height) / 2
            let path = CGMutablePath()
            for i in 0..<3 {
                let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 3
                let pt = CGPoint(x: cx + rad * cos(angle), y: cy + rad * sin(angle))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            return path
        }
    }

    /// 序号标注：实心标记 + 白色数字
    private static func drawNumber(_ ctx: CGContext, _ n: Int, center: CGPoint,
                                   diameter: CGFloat, shape: NumberShape, color: NSColor) {
        let d = max(18, diameter)
        let r = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        ctx.saveGState()
        // 描一圈白边，保证在任何底色上都看得清
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.addPath(numberPath(shape, in: r.insetBy(dx: -1.5, dy: -1.5)))
        ctx.fillPath()
        ctx.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
        ctx.addPath(numberPath(shape, in: r))
        ctx.fillPath()

        let text = "\(n)"
        let fontSize = d * 0.52
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))

        // 必须用 .useGlyphPathBounds —— 它是**字形轮廓**的包围盒。
        // 踩过的两个坑：
        //  · .useOpticalBounds 返回的其实是整个行盒（y 从降部到升部、x 是完整前进宽度），
        //    用它定位会把基线压到圆心下方约 28pt，数字直接溢出圆外。
        //  · 用前进宽度居中也不行：数字 "1" 的墨迹中心在 7.20，前进宽度中心在 8.51，
        //    实测偏 3.5 像素。
        // 轮廓包围盒对任何字形都精确：把它的中心对准圆心即可。
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textMatrix = .identity
        ctx.translateBy(x: center.x - ink.midX, y: center.y + ink.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// 聚焦高亮：整屏压暗，把聚焦区挖空，并描一圈边框
    private static func drawSpotlight(_ ctx: CGContext, _ r: CGRect) {
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(CGRect(x: -20000, y: -20000, width: 40000, height: 40000))
        path.addRect(r)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55).cgColor)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(r)
        ctx.restoreGState()
    }

    private static func drawCheck(_ ctx: CGContext, center: CGPoint, size: CGFloat, width: CGFloat) {
        let s = max(14, size)
        let c = Palette.checkGreen
        let p1 = CGPoint(x: center.x - s * 0.42, y: center.y + s * 0.02)
        let p2 = CGPoint(x: center.x - s * 0.10, y: center.y + s * 0.34)
        let p3 = CGPoint(x: center.x + s * 0.44, y: center.y - s * 0.36)
        ctx.saveGState()
        ctx.setStrokeColor(c.cgColor)
        ctx.setLineWidth(max(2, max(width, s * 0.14)))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.beginPath(); ctx.move(to: p1); ctx.addLine(to: p2); ctx.addLine(to: p3); ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawCross(_ ctx: CGContext, center: CGPoint, size: CGFloat, width: CGFloat) {
        let s = max(14, size)
        let c = Palette.crossRed
        let d = s * 0.40
        ctx.saveGState()
        ctx.setStrokeColor(c.cgColor)
        ctx.setLineWidth(max(2, max(width, s * 0.14)))
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x - d, y: center.y - d)); ctx.addLine(to: CGPoint(x: center.x + d, y: center.y + d))
        ctx.move(to: CGPoint(x: center.x + d, y: center.y - d)); ctx.addLine(to: CGPoint(x: center.x - d, y: center.y + d))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - 打码滤镜

enum Redact {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 对一小块底图应用打码滤镜。
    /// 关键点：高斯模糊必须先 `clampedToExtent()`，否则边缘采样不到内容会发暗
    /// （这是 CIGaussianBlur 最经典的坑，表现为打码区四周出现一圈灰边）。
    static func filter(_ img: CGImage, style: RedactStyle) -> CGImage? {
        let src = CIImage(cgImage: img)
        let extent = src.extent
        guard extent.width >= 1, extent.height >= 1 else { return nil }

        let out: CIImage?
        switch style {
        case .blur:
            out = src.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14.0])
                .cropped(to: extent)
        case .pixelate:
            out = src.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 12.0])
                .cropped(to: extent)
        }
        guard let o = out else { return nil }
        return ciContext.createCGImage(o, from: extent)
    }
}

// MARK: - 标注图层（透明位图，橡皮擦用 .clear 混合挖空）

final class AnnotationLayer {
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat
    let ctx: CGContext
    /// 以点为单位、左上角为原点、y 轴向下的逻辑尺寸
    var pointSize: CGSize { CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale) }

    /// 打码需要读取底图。由 CanvasState 注入 —— 底图会随「空白纸 / 剪贴板」变化，
    /// 所以这里用闭包每次取当前值，而不是持有快照。
    var backgroundProvider: (() -> CGImage?)?
    var backgroundScale: CGFloat = 2

    init?(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let c = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.ctx = c
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: 0, y: CGFloat(pixelHeight) / scale)
        c.scaleBy(x: 1, y: -1)
        c.setShouldAntialias(true)
    }

    func clear() {
        ctx.clear(CGRect(x: 0, y: 0, width: pointSize.width, height: pointSize.height))
    }

    func apply(_ stroke: Stroke) {
        if case .redact(let rect, let style) = stroke.shape {
            applyRedaction(rect: rect, style: style)
        } else {
            ShapeRenderer.draw(stroke, in: ctx)
        }
    }

    /// 把 rect 区域内的底图抠出来做打码，再贴回标注层。
    /// 这样打码结果是"烘焙"进图层的，后续画的笔迹自然压在它上面，撤销重放也一致。
    private func applyRedaction(rect: CGRect, style: RedactStyle) {
        guard rect.width > 2, rect.height > 2, let bg = backgroundProvider?() else { return }
        let s = backgroundScale
        let px = CGRect(x: rect.minX * s, y: rect.minY * s,
                        width: rect.width * s, height: rect.height * s).integral
        let clamped = px.intersection(CGRect(x: 0, y: 0, width: bg.width, height: bg.height))
        guard clamped.width >= 2, clamped.height >= 2,
              let sub = bg.cropping(to: clamped),
              let filtered = Redact.filter(sub, style: style) else { return }

        // 被图像边界截断时，贴回的位置要按比例折算
        let drawRect = CGRect(x: clamped.minX / s, y: clamped.minY / s,
                              width: clamped.width / s, height: clamped.height / s)
        ctx.saveGState()
        ctx.translateBy(x: drawRect.minX, y: drawRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(filtered, in: CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height))
        ctx.restoreGState()
    }

    func rebuild(from strokes: [Stroke]) {
        clear()
        // 聚焦高亮只让**最后一个**生效。
        // 否则每框一次就叠一层 55% 的黑，画面会一层层变暗 —— 用户看到的"累积变暗"。
        var lastSpotlight = -1
        for (i, s) in strokes.enumerated() {
            if case .spotlight = s.shape { lastSpotlight = i }
        }
        for (i, s) in strokes.enumerated() {
            if case .spotlight = s.shape, i != lastSpotlight { continue }
            apply(s)
        }
    }

    func snapshot() -> CGImage? { ctx.makeImage() }
}
