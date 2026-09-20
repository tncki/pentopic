// Toolbar.swift — 竖排双列工具栏（还原 Pointofix 原版布局）
import SwiftUI

// MARK: - 窗口拖动区

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class DragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        if let o = window?.frame.origin { Prefs.setToolbarOrigin(o) }
    }
}

// MARK: - 基础按钮

private struct TButton<Content: View>: View {
    let help: String
    let active: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Content

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: Prefs.buttonW, height: Prefs.buttonH)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor.opacity(0.9)
                                     : Color(NSColor.controlBackgroundColor).opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? Color.white.opacity(0.7) : Color.black.opacity(0.28), lineWidth: 1)
                )
                .foregroundColor(active ? .white : Color(NSColor.labelColor))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ToolButton: View {
    let tool: ToolKind
    let active: Bool
    let action: () -> Void

    // 原版：对勾为绿色、叉号为红色
    private var tint: Color? {
        switch tool {
        case .check: return active ? .white : Color(nsColor: Palette.checkGreen)
        case .cross: return active ? .white : Color(nsColor: Palette.crossRed)
        default: return nil
        }
    }

    var body: some View {
        TButton(help: "\(tool.title)  (\(tool.shortcutHint))", active: active, action: action) {
            if tool == .text {
                // 原版文字工具就是一个大写的 “A”（SF Symbol textformat 会随语言变成本地字形）
                Text("A")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(active ? .white : Color(NSColor.labelColor))
            } else {
                Image(systemName: tool.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }
        }
    }
}

private struct ActionButton: View {
    let symbol: String
    let help: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        TButton(help: help, active: false, action: { if enabled { action() } }) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .opacity(enabled ? 1 : 0.35)
        }
    }
}

// MARK: - 颜色块

private struct SwatchButton: View {
    let swatch: Swatch
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color.white)
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: swatch.color))
            }
            .frame(width: Prefs.buttonW, height: Prefs.buttonH * 0.72)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(active ? Color.accentColor : Color.black.opacity(0.35),
                            lineWidth: active ? 3 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(swatch.isOpaque ? LS("Deckende Farbe", "Opaque color", "不透明色", "不透明色")
                              : LS("Transparente Farbe", "Transparent color", "透明色", "透明色"))
    }
}

// MARK: - 笔粗

private struct SizeButton: View {
    let index: Int
    let active: Bool
    let action: () -> Void
    var body: some View {
        let d = 4 + CGFloat(index) * 4.5
        TButton(help: "\(LS("Stiftgröße", "Pen size", "笔粗", "筆刷大小")) \(index + 1)  (\(index + 1))", active: active, action: action) {
            Circle()
                .fill(Color(NSColor.labelColor))
                .frame(width: d, height: d)
        }
    }
}

// MARK: - 主工具栏

struct ToolbarView: View {
    @ObservedObject var model: ToolbarModel
    let controller: SessionController

    private var cols: [[Swatch]] {
        stride(from: 0, to: model.swatches.count, by: 2).map {
            Array(model.swatches[$0..<min($0 + 2, model.swatches.count)])
        }
    }

    private var rowPairs: [(ToolKind, ToolKind)] {
        [(.pen, .eraser), (.line, .arrow), (.rect, .rectFilled), (.ellipse, .ellipseFilled),
         (.doubleArrow, .text), (.check, .cross),
         (.number, .spotlight), (.blur, .pixelate),        // 序号 / 聚焦 / 两种打码
         (.region, .magnifier), (.zoomIn, .zoomOut)]
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            startButton
            if model.isActive {
                Divider().background(Color.black.opacity(0.3))
                sizeGrid
                Divider().background(Color.black.opacity(0.3))
                colorGrid
                Divider().background(Color.black.opacity(0.3))
                toolGrid
                Divider().background(Color.black.opacity(0.3))
                actionGrid
            }
        }
        .padding(6)
        .frame(width: Prefs.buttonW * 2 + 18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.sRGB, red: 0.25, green: 0.35, blue: 0.6, opacity: 1), lineWidth: 1.5)
        )
    }

    // 标题栏（可拖动）
    private var header: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 4) {
                Text(Brand.name).font(.system(size: 9.5, weight: .bold)).lineLimit(1)
                    .foregroundColor(Color(.sRGB, red: 0.2, green: 0.3, blue: 0.6, opacity: 1))
                Spacer(minLength: 0)
                Button(action: { controller.finish() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(.sRGB, red: 0.8, green: 0.2, blue: 0.18, opacity: 1))
                }
                .buttonStyle(.plain)
                .help(LS("Beenden (F9)", "Finish (F9)", "结束标注 (F9)", "結束標註 (F9)"))
            }
        }
        .frame(height: 18)
    }

    private var startButton: some View {
        Button(action: { controller.toggle() }) {
            Text(model.isActive ? LS("Fertig", "Finish", "完成", "完成") : LS("Start", "Start", "开始", "開始"))
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(LS("Start / Fertig  (F9)", "Start / Finish  (F9)", "开始 / 完成  (F9)", "開始 / 完成  (F9)"))
    }

    private var sizeGrid: some View {
        VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { col in
                        let i = row * 2 + col
                        if i < PenSize.count {
                            SizeButton(index: i, active: model.penSizeIndex == i) {
                                controller.setPenSize(i)
                            }
                        }
                    }
                }
            }
        }
    }

    private var colorGrid: some View {
        VStack(spacing: 3) {
            ForEach(Array(cols.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 3) {
                    ForEach(Array(pair.enumerated()), id: \.offset) { _, sw in
                        let idx = model.swatches.firstIndex(where: { $0.base == sw.base && $0.alpha == sw.alpha }) ?? 0
                        SwatchButton(swatch: sw, active: model.swatchIndex == idx) {
                            controller.setSwatch(idx)
                        }
                    }
                    if pair.count == 1 { Spacer().frame(width: Prefs.buttonW) }
                }
            }
        }
    }

    private var toolGrid: some View {
        VStack(spacing: 3) {
            ForEach(Array(rowPairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 3) {
                    ToolButton(tool: pair.0, active: model.tool == pair.0) { controller.setTool(pair.0) }
                    ToolButton(tool: pair.1, active: model.tool == pair.1) { controller.setTool(pair.1) }
                }
            }
        }
    }

    /// 操作区。工具栏是固定两列宽（Prefs.buttonW * 2 + 间距），
    /// 所以**每行必须恰好两个按钮** —— 放三个会被 SwiftUI 压缩变形。
    private var actionGrid: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ActionButton(symbol: "arrow.uturn.backward",
                             help: LS("Rückgängig (⌘Z)", "Undo (⌘Z)", "撤销 (⌘Z)", "復原 (⌘Z)"),
                             enabled: model.canUndo) { controller.undo() }
                ActionButton(symbol: "arrow.uturn.forward",
                             help: LS("Wiederholen (⇧⌘Z)", "Redo (⇧⌘Z)", "重做 (⇧⌘Z)", "重做 (⇧⌘Z)"),
                             enabled: model.canRedo) { controller.redo() }
            }
            HStack(spacing: 3) {
                ActionButton(symbol: "trash",
                             help: LS("Alles löschen", "Clear all", "清空标注", "清空標註"),
                             enabled: model.hasStrokes) { controller.clearAll() }
                sheetMenu
            }
            HStack(spacing: 3) {
                ActionButton(symbol: "doc.on.clipboard",
                             help: LS("In Zwischenablage kopieren (⌘C)", "Copy to clipboard (⌘C)", "复制到剪贴板 (⌘C)", "複製到剪貼簿 (⌘C)")) {
                    Exporter.copyToClipboard(controller.activeCanvas)
                }
                ActionButton(symbol: "printer",
                             help: LS("Drucken (⌘P)", "Print (⌘P)", "打印 (⌘P)", "列印 (⌘P)")) {
                    Exporter.print(controller.activeCanvas)
                }
            }
            HStack(spacing: 3) {
                saveMenu
                mailMenu
            }
            HStack(spacing: 3) {
                ActionButton(symbol: "info.circle",
                             help: LS("Info & Einstellungen", "Info & settings", "信息与设置", "資訊與設定")) {
                    SettingsWindowController.shared.show()
                }
                Spacer().frame(width: Prefs.buttonW)
            }
        }
    }

    // MARK: 下拉菜单按钮（复用同一套外观）

    private var sheetMenu: some View {
        Menu {
            ForEach(BackgroundKind.allCases, id: \.self) { k in
                Button {
                    if k == .clipboard { controller.pasteFromClipboard() } else { controller.setBackground(k) }
                } label: {
                    Label(k.title, systemImage: k.symbol)
                }
            }
        } label: {
            Image(systemName: "doc")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Prefs.buttonW, height: Prefs.buttonH)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor).opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.28), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Prefs.buttonW, height: Prefs.buttonH)
        .help(LS("Neues Blatt", "New sheet", "新建纸", "新建紙"))
    }

    private var saveMenu: some View {
        Menu {
            Button(LS("Speichern unter … (⌘S)", "Save as … (⌘S)", "另存为 … (⌘S)", "另存新檔 … (⌘S)")) {
                Exporter.saveWithPanel(controller.activeCanvas, screen: controller.activeCanvas?.screen)
            }
            Divider()
            Button(LS("Als PNG im Screenshot-Ordner ablegen", "Save PNG to screenshots folder", "存为 PNG 到截图文件夹", "儲存 PNG 到截圖資料夾")) {
                Exporter.saveToFolder(controller.activeCanvas, format: .png)
            }
            Button(LS("Als JPG im Screenshot-Ordner ablegen", "Save JPG to screenshots folder", "存为 JPG 到截图文件夹", "儲存 JPG 到截圖資料夾")) {
                Exporter.saveToFolder(controller.activeCanvas, format: .jpg)
            }
            Divider()
            Button(LS("Screenshot-Ordner öffnen (⌘O)", "Open screenshots folder (⌘O)", "打开截图文件夹 (⌘O)", "開啟截圖資料夾 (⌘O)")) {
                Exporter.openScreenshotFolder()
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Prefs.buttonW, height: Prefs.buttonH)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor).opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.28), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Prefs.buttonW, height: Prefs.buttonH)
        .help(LS("Speichern", "Save", "保存", "儲存"))
    }

    private var mailMenu: some View {
        Menu {
            Button(LS("Bild per E-Mail senden", "Send image by e-mail", "邮件发送图片", "郵件傳送圖片")) {
                Exporter.composeMail(controller.activeCanvas, openFolderFirst: false)
            }
            Button(LS("E-Mail-Programm und Ordner öffnen (⌘E)", "Open mail app and folder (⌘E)", "打开邮件程序与文件夹 (⌘E)", "開啟郵件程式與資料夾 (⌘E)")) {
                Exporter.composeMail(controller.activeCanvas, openFolderFirst: true)
            }
        } label: {
            Image(systemName: "envelope")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Prefs.buttonW, height: Prefs.buttonH)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor).opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.28), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Prefs.buttonW, height: Prefs.buttonH)
        .help(LS("Per E-Mail senden", "Send by e-mail", "邮件发送", "郵件傳送"))
    }
}

