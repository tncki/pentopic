// SettingsWindow.swift — 信息与设置（对应原版 “i” → Einstellungen）
import SwiftUI
import Carbon.HIToolbox

final class SettingsModel: ObservableObject {
    @Published var language: String = "auto"
    @Published var cursorMode: Int = 0
    @Published var wheelZoom = true
    @Published var autoOpen = false
    @Published var quitOnFinish = false
    @Published var autoScreenshot = false
    @Published var autoScreenshotFormat = "png"
    @Published var screenMode = 0
    @Published var screenshotFolder = ""
    @Published var emailFolder = ""
    @Published var buttonW: Double = 30
    @Published var buttonH: Double = 30
    @Published var extraColors: [String] = []
    @Published var filenameTemplate = "{app}-{date}-{time}"
    @Published var captureDelay = 0
    @Published var captureCursor = false
    @Published var watermark = ""
    @Published var fixedRegion = ""
    @Published var freeRegion = false
    @Published var frameStyle = "none"
    @Published var historyEnabled = true
    @Published var historyLimit = 20
    @Published var hotKeySpec: HotKeySpec = .default
    @Published var hotKeyWarning: String?

    func load() {
        language = Prefs.language?.rawValue ?? "auto"
        cursorMode = Prefs.cursorMode.rawValue
        wheelZoom = Prefs.wheelZoom
        autoOpen = Prefs.autoOpen
        quitOnFinish = Prefs.quitOnFinish
        autoScreenshot = Prefs.autoScreenshot
        autoScreenshotFormat = Prefs.autoScreenshotFormat
        screenMode = Prefs.screenMode.rawValue
        screenshotFolder = Prefs.screenshotFolder.path
        emailFolder = Prefs.emailFolder.path
        buttonW = Double(Prefs.buttonW)
        buttonH = Double(Prefs.buttonH)
        extraColors = Prefs.extraColors
        filenameTemplate = Prefs.filenameTemplate
        captureDelay = Prefs.captureDelay
        captureCursor = Prefs.captureCursor
        watermark = Prefs.watermark
        fixedRegion = Prefs.fixedRegion
        freeRegion = Prefs.freeRegion
        frameStyle = Prefs.frameStyle
        historyEnabled = Prefs.historyEnabled
        historyLimit = Prefs.historyLimit
        hotKeySpec = Prefs.hotKeySpec
        hotKeyWarning = Prefs.hotKeySpec.conflictWarning
    }

    func save() {
        Prefs.language = (language == "auto") ? nil : AppLang(rawValue: language)
        L.lang = Prefs.resolveLanguage()
        Prefs.cursorMode = CursorMode(rawValue: cursorMode) ?? .normal
        Prefs.wheelZoom = wheelZoom
        Prefs.autoOpen = autoOpen
        Prefs.quitOnFinish = quitOnFinish
        Prefs.autoScreenshot = autoScreenshot
        Prefs.autoScreenshotFormat = autoScreenshotFormat
        Prefs.screenMode = ScreenMode(rawValue: screenMode) ?? .mouse
        Prefs.buttonW = CGFloat(buttonW)
        Prefs.buttonH = CGFloat(buttonH)
        // 之前这里漏了 —— load() 读了但 save() 从没写回，导致「选择…」改的目录点确定就丢
        Prefs.setScreenshotFolder(URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath))
        Prefs.setEmailFolder(URL(fileURLWithPath: (emailFolder as NSString).expandingTildeInPath))
        Prefs.filenameTemplate = filenameTemplate.isEmpty ? "{app}-{date}-{time}" : filenameTemplate
        Prefs.captureDelay = captureDelay
        Prefs.captureCursor = captureCursor
        Prefs.watermark = watermark
        Prefs.fixedRegion = fixedRegion
        Prefs.freeRegion = freeRegion
        Prefs.frameStyle = frameStyle
        Prefs.historyEnabled = historyEnabled
        Prefs.historyLimit = historyLimit
        CaptureHistory.prune()
        Prefs.extraColors = extraColors
        Prefs.ensureFolders()
        if hotKeySpec != Prefs.hotKeySpec {
            Prefs.hotKeySpec = hotKeySpec
            GlobalHotKey.shared.register(hotKeySpec)
        }
        SessionController.shared.onToolChanged()
        SessionController.shared.rebuildToolbar()
    }
}

struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group(LS("Programmstart und -ende", "Startup and exit", "启动与退出", "啟動與結束")) {
                        Toggle(LS("Zeichenfunktionen sofort bei Programmstart öffnen",
                                  "Open drawing tools immediately at startup",
                                  "启动时立即进入标注模式", "啟動時立即進入標註模式"), isOn: $m.autoOpen)
                        Toggle(LS("Mit Klick auf 'Fertig' [F9] Programm beenden",
                                  "Quit program when clicking 'Finish' [F9]",
                                  "点击“完成”[F9] 后退出程序", "按一下“完成”[F9] 後結束程式"), isOn: $m.quitOnFinish)
                        Toggle(LS("Auto-Screenshot beim Klick auf 'Fertig' [F9]",
                                  "Auto screenshot on clicking 'Finish' [F9]",
                                  "点击“完成”[F9] 时自动截图", "按一下“完成”[F9] 時自動截圖"), isOn: $m.autoScreenshot)
                        HStack {
                            Text(LS("Format", "Format", "格式", "格式")).frame(width: 120, alignment: .leading)
                            Picker("", selection: $m.autoScreenshotFormat) {
                                Text("PNG").tag("png")
                                Text("JPG").tag("jpg")
                            }.pickerStyle(.segmented).frame(width: 140)
                        }
                    }

                    group(LS("Mauszeiger und Zoom", "Cursor and zoom", "光标与缩放", "游標與縮放")) {
                        HStack {
                            Text(LS("Mauszeiger auf Zeichenfläche", "Cursor on canvas", "画布上的鼠标指针", "畫布上的滑鼠指標"))
                                .frame(width: 210, alignment: .leading)
                            Picker("", selection: $m.cursorMode) {
                                Text(LS("Normal", "Normal", "正常", "正常")).tag(0)
                                Text(LS("Ausgeblendet (Werkzeugsymbol)", "Hidden (tool symbol)", "隐藏（显示工具符号）", "隱藏（顯示工具符號）")).tag(1)
                            }.labelsHidden().frame(width: 240)
                        }
                        Toggle(LS("Zoomansicht: Mausrad zum Zoomen verwenden",
                                  "Zoom view: use mouse wheel to zoom",
                                  "缩放视图：使用滚轮缩放", "縮放檢視：使用滾輪縮放"), isOn: $m.wheelZoom)
                    }

                    group(LS("Mehrere Bildschirme", "Multiple displays", "多显示器", "多螢幕")) {
                        HStack {
                            Text(LS("Zeichenfläche", "Drawing surface", "标注画布", "標註畫布")).frame(width: 120, alignment: .leading)
                            Picker("", selection: $m.screenMode) {
                                Text(LS("Bildschirm mit dem Start-Knopf", "Screen with the Start button", "按下开始按钮所在屏幕", "按下開始按鈕所在螢幕")).tag(0)
                                Text(LS("Immer erster Bildschirm", "Always first display", "始终第一块屏幕", "始終第一塊螢幕")).tag(1)
                                Text(LS("Immer zweiter Bildschirm", "Always second display", "始终第二块屏幕", "始終第二塊螢幕")).tag(2)
                            }.labelsHidden().frame(width: 280)
                        }
                    }

                    group(LS("Größe der Werkzeugschaltflächen", "Tool button size", "工具按钮尺寸", "工具按鈕大小")) {
                        HStack {
                            Text(LS("Breite", "Width", "宽度", "寬度")).frame(width: 60, alignment: .leading)
                            Slider(value: $m.buttonW, in: 22...56, step: 1).frame(width: 160)
                            Text("\(Int(m.buttonW)) px").frame(width: 60)
                        }
                        HStack {
                            Text(LS("Höhe", "Height", "高度", "高度")).frame(width: 60, alignment: .leading)
                            Slider(value: $m.buttonH, in: 22...56, step: 1).frame(width: 160)
                            Text("\(Int(m.buttonH)) px").frame(width: 60)
                        }
                    }

                    group(LS("Dateiname und Aufnahme", "Filename and capture", "文件名与捕捉", "檔名與捕捉")) {
                        HStack(spacing: 8) {
                            Text(LS("Namensvorlage", "Name template", "命名模板", "命名範本"))
                                .frame(width: 150, alignment: .leading)
                            TextField("", text: $m.filenameTemplate)
                                .frame(width: 230)
                                .onSubmit { m.save() }
                        }
                        Text(LS("Platzhalter: {app} Programmname · {date} Datum · {time} Uhrzeit · {n} laufende Nummer",
                                "Placeholders: {app} app name · {date} date · {time} time · {n} running number",
                                "占位符：{app} 程序名 · {date} 日期 · {time} 时间 · {n} 序号",
                                "佔位符：{app} 程式名 · {date} 日期 · {time} 時間 · {n} 序號"))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                        Text(LS("Vorschau:", "Preview:", "预览：", "預覽：") + " "
                             + Exporter.renderBaseName(index: 1) + ".png")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text(LS("Verzögerte Aufnahme", "Delayed capture", "延时捕捉", "延時捕捉"))
                                .frame(width: 150, alignment: .leading)
                            Picker("", selection: $m.captureDelay) {
                                Text(LS("Sofort", "Immediately", "立即", "立即")).tag(0)
                                Text("3 s").tag(3)
                                Text("5 s").tag(5)
                                Text("10 s").tag(10)
                            }.labelsHidden().frame(width: 120)
                        }
                    }

                    group(LS("Ausgabe", "Output", "输出效果", "輸出效果")) {
                        Toggle(LS("Mauszeiger mit aufnehmen", "Include the mouse pointer",
                                  "截图时包含鼠标指针", "截圖時包含滑鼠指標"),
                               isOn: $m.captureCursor)
                        HStack(spacing: 8) {
                            Text(LS("Wasserzeichen", "Watermark", "水印文字", "浮水印文字"))
                                .frame(width: 150, alignment: .leading)
                            TextField(LS("leer = kein Wasserzeichen", "empty = no watermark",
                                         "留空 = 不加水印", "留空 = 不加水印"),
                                      text: $m.watermark)
                                .frame(width: 230)
                                .onSubmit { m.save() }
                        }
                        HStack(spacing: 8) {
                            Text(LS("Bereichsgröße", "Region size", "选区尺寸", "選取範圍尺寸"))
                                .frame(width: 150, alignment: .leading)
                            TextField(LS("z. B. 800x600, leer = frei", "e.g. 800x600, empty = free",
                                         "如 800x600，留空 = 自由拖拽", "如 800x600，留空 = 自由拖曳"),
                                      text: $m.fixedRegion)
                                .frame(width: 180)
                                .onSubmit { m.save() }
                            Toggle(LS("Freihand", "Freehand", "自由手绘", "自由手繪"), isOn: $m.freeRegion)
                        }
                        HStack(spacing: 8) {
                            Text(LS("Rahmen", "Frame", "装饰边框", "裝飾邊框"))
                                .frame(width: 150, alignment: .leading)
                            Picker("", selection: $m.frameStyle) {
                                ForEach(FrameStyle.allCases, id: \.rawValue) { f in
                                    Text(f.title).tag(f.rawValue)
                                }
                            }.labelsHidden().frame(width: 160)
                        }
                        Text(LS("Wasserzeichen und Rahmen wirken nur auf gespeicherte/versendete Bilder, nicht auf die Arbeitsfläche.",
                                "Watermark and frame apply to saved or shared images only, not to the canvas.",
                                "水印与边框只作用于导出/发送的图片，不影响标注画布。",
                                "浮水印與邊框只作用於匯出/傳送的圖片，不影響標註畫布。"))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }

                    group(LS("Aufnahmeverlauf", "Capture history", "捕捉历史", "捕捉歷史")) {
                        Toggle(LS("Jede beendete Aufnahme automatisch sichern",
                                  "Save every finished capture automatically",
                                  "每次结束捕捉时自动存档",
                                  "每次結束捕捉時自動存檔"),
                               isOn: $m.historyEnabled)
                        HStack(spacing: 8) {
                            Text(LS("Behalten", "Keep", "保留张数", "保留張數"))
                                .frame(width: 150, alignment: .leading)
                            Picker("", selection: $m.historyLimit) {
                                ForEach([5, 10, 20, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                            }.labelsHidden().frame(width: 100)
                            Button(LS("Verlauf öffnen …", "Open history …", "打开历史 …", "開啟歷史 …")) {
                                HistoryWindowController.shared.show()
                            }
                        }
                    }

                    group(LS("Ordner", "Folders", "文件夹", "資料夾")) {
                        folderRow(LS("Screenshot-Ordner", "Screenshot folder", "截图文件夹", "截圖資料夾"),
                                  path: $m.screenshotFolder) { m.screenshotFolder = $0 }
                        folderRow(LS("E-Mail-Zwischenspeicher", "E-mail temp folder", "邮件临时文件夹", "郵件臨時資料夾"),
                                  path: $m.emailFolder) { m.emailFolder = $0 }
                    }

                    group(LS("Zusätzliche Farben (max. 10)", "Additional colors (max 10)", "附加颜色（最多 10 个）", "其他顏色（最多 10 個）")) {
                        HStack(spacing: 8) {
                            ForEach(Array(m.extraColors.enumerated()), id: \.offset) { idx, hex in
                                Button {
                                    ColorPanelBridge.shared.pick(from: hex) { newHex in
                                        if idx < m.extraColors.count { m.extraColors[idx] = newHex }
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(nsColor: NSColor(hex: hex) ?? .red))
                                        .frame(width: 30, height: 22)
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.black.opacity(0.35), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help(LS("Farbe wählen", "Choose colour", "选择颜色", "選擇顏色"))
                            }
                            if m.extraColors.count < 10 {
                                Button {
                                    m.extraColors.append("#FF7A00")
                                } label: { Image(systemName: "plus.circle") }
                                    .buttonStyle(.plain)
                            }
                            if !m.extraColors.isEmpty {
                                Button {
                                    m.extraColors.removeLast()
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain)
                            }
                        }
                        Text(LS("Diese Farben erscheinen zusätzlich unterhalb der Standardfarben.",
                                "These colors appear below the standard colors.",
                                "这些颜色会显示在标准颜色下方。", "這些顏色會顯示在標準顏色下方。"))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }

                    group(LS("Sprache / Language", "Language", "语言", "語言")) {
                        Picker("", selection: $m.language) {
                            Text(LS("Automatisch", "Automatic", "自动", "自動")).tag("auto")
                            ForEach(AppLang.selectable, id: \.rawValue) { l in
                                Text(l.label).tag(l.rawValue)
                            }
                        }.labelsHidden().frame(width: 220)
                    }
                    group(LS("Globaler Kurzbefehl (Start/Fertig)", "Global hotkey (start/finish)", "全局热键（开始/完成）", "全域快速鍵（開始/完成）")) {
                        HStack(spacing: 8) {
                            HotKeyRecorder(spec: $m.hotKeySpec) { m.hotKeyWarning = $0 }
                                .frame(width: 200, height: 26)
                            Button(LS("Zurücksetzen", "Reset", "重置", "重設")) {
                                m.hotKeySpec = .default
                                m.hotKeyWarning = nil
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                            Spacer()
                        }
                        Text(LS("Anklicken und dann die gewünschte Tastenkombination drücken. ESC bricht ab.",
                                "Click, then press the key combination you want. ESC cancels.",
                                "点一下，然后按下你想要的组合键。按 ESC 取消。",
                                "點一下，然後按下你想要的組合鍵。按 ESC 取消。"))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                        if let w = m.hotKeyWarning {
                            Text(w)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    about
                }
                .padding(16)
            }
            footer
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(LS("\(Brand.name) für macOS", "\(Brand.name) for macOS", "\(Brand.name) macOS 版", "\(Brand.name) macOS 版")).font(.system(size: 15, weight: .bold))
                Text(LS("Der virtuelle Textmarker für Ihren Bildschirm",
                        "The virtual highlighter for your screen",
                        "你的屏幕虚拟荧光笔", "你的螢幕虛擬螢光筆")).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    var about: some View {   // internal：供离屏预览单独渲染
        VStack(alignment: .leading, spacing: 4) {
            Text(LS("Über", "About", "关于", "關於")).font(.system(size: 12, weight: .semibold))
            Text("\(Brand.name) \(Brand.version)")
                .font(.system(size: 11, weight: .medium))
            Text(Brand.copyright)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LS("Lizenz: MIT", "Licence: MIT", "许可证：MIT", "授權條款：MIT"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(LS("""
            Unabhängige macOS-Anwendung für Bildschirm-Annotationen.
            Inspiriert von \(Brand.upstreamName) 1.8 von \(Brand.upstreamAuthor) — ohne Verbindung zum Original.
            Tastenkürzel: B Stift · E Radierer · G Linie · P Pfeil · D Doppelpfeil · R Rechteck (⇧ gefüllt) ·
            O Ellipse (⇧ gefüllt) · T Text · H Häkchen · K Kreuz · F Bereich · M Lupe · +/− Zoom · F2 Bereich
            eingeben · F9 Start/Fertig · ⌘Z Rückgängig · ⌘C Kopieren · ⌘S Speichern · ⌘P Drucken · ⌘V Einfügen.
            """, """
            Independent macOS screen-annotation app.
            Inspired by \(Brand.upstreamName) 1.8 by \(Brand.upstreamAuthor) — not affiliated with the original.
            Shortcuts: B pen · E eraser · G line · P arrow · D double arrow · R rectangle (⇧ filled) ·
            O ellipse (⇧ filled) · T text · H check · K cross · F region · M magnifier · +/− zoom · F2 enter
            region · F9 start/finish · ⌘Z undo · ⌘C copy · ⌘S save · ⌘P print · ⌘V paste.
            """, """
            独立的 macOS 屏幕标注应用。
            受 \(Brand.upstreamAuthor) 的 \(Brand.upstreamName) 1.8 启发 —— 与原作无隶属关系。
            快捷键：B 画笔 · E 橡皮 · G 直线 · P 箭头 · D 双向箭头 · R 矩形（⇧ 实心）· O 椭圆（⇧ 实心）·
            T 文字 · H 对勾 · K 叉号 · F 选区 · M 放大镜 · +/− 缩放 · F2 输入选区坐标 · F9 开始/完成 ·
            ⌘Z 撤销 · ⌘C 复制 · ⌘S 保存 · ⌘P 打印 · ⌘V 粘贴。
            """, """
            獨立的 macOS 螢幕標註應用。
            受 \(Brand.upstreamAuthor) 的 \(Brand.upstreamName) 1.8 啟發 —— 與原作無隸屬關係。
            快速鍵：B 筆刷 · E 橡皮 · G 直線 · P 箭頭 · D 雙向箭頭 · R 矩形（⇧ 實心）· O 橢圓（⇧ 實心）·
            T 文字 · H 打勾 · K 叉號 · F 選取範圍 · M 放大鏡 · +/− 縮放 · F2 輸入選取範圍座標 · F9 開始/完成 ·
            ⌘Z 復原 · ⌘C 複製 · ⌘S 儲存 · ⌘P 列印 · ⌘V 貼上。
            """))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(Brand.upstreamURL, destination: URL(string: Brand.upstreamURL)!)
                .font(.system(size: 10))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(LS("Abbrechen", "Cancel", "取消", "取消")) { onClose() }
            Button(LS("OK", "OK", "确定", "確定")) { m.save(); onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
    }

    @ViewBuilder
    private func folderRow(_ label: String, path: Binding<String>, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 150, alignment: .leading)
            Text(path.wrappedValue)
                .font(.system(size: 10))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.textBackgroundColor)))
            Button(LS("Wählen …", "Choose …", "选择 …", "選擇 …")) {
                let p = NSOpenPanel()
                p.canChooseDirectories = true
                p.canChooseFiles = false
                p.allowsMultipleSelection = false
                p.canCreateDirectories = true
                // 用 sheet 挂在设置窗口上：sheet 必然位于所属窗口之上，不受窗口层级影响。
                // 之前用 runModal + 手动设 level，但会话期间设置窗口在 screenSaver+4，
                // 面板会被压在下面看不见 —— 用户看到的就是"点了没反应"。
                if let host = NSApp.keyWindow ?? NSApp.mainWindow {
                    p.beginSheetModal(for: host) { resp in
                        if resp == .OK, let u = p.url { set(u.path) }
                    }
                } else if p.runModal() == .OK, let u = p.url {
                    set(u.path)
                }
            }
        }
    }
}

// MARK: - 附加颜色：自己管理系统颜色面板
//
// 原先用 SwiftUI 的 ColorPicker，它内部是 NSColorWell + 共享的 NSColorPanel：
//   · NSColorPanel 是浮动面板，**不会随「信息与设置」窗口关闭而消失**，
//     会一直遗留在屏幕上 —— 用户看到的现象就是"点开始先蹦出一个颜色面板"
//   · 取色经过 SwiftUI Binding 转发，链路不可控、也不便排查
// 改为自己持有 NSColorPanel，明确控制打开与关闭，取色走 target/action 直达。
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var onPick: ((String) -> Void)?
    private var active = false

    func pick(from hex: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        let panel = NSColorPanel.shared
        // NSColorPanel 是 .floating 层级。会话期间设置窗口在 screenSaver+4，
        // 不抬高的话颜色面板会被压在设置窗口下面，表现为"点了没反应"。
        panel.level = NSWindow.Level(rawValue: (NSApp.keyWindow?.level.rawValue ?? 0) + 2)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.showsAlpha = false          // 附加颜色都是不透明的
        panel.isContinuous = true
        panel.color = NSColor(hex: hex) ?? .red
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
        active = true
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onPick?(sender.color.hexString)
    }

    /// 跟随设置窗口的层级，保证颜色面板始终在它上面
    func updateLevel(above level: NSWindow.Level) {
        guard active else { return }
        NSColorPanel.shared.level = NSWindow.Level(rawValue: level.rawValue + 2)
    }

    /// 设置窗口关闭时必须调用，否则颜色面板会遗留在屏幕上
    func dismiss() {
        guard active else { return }
        active = false
        onPick = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.orderOut(nil)
    }
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        model.load()
        let view = SettingsView(m: model) { [weak self] in
            self?.closeWindow()
        }
        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = LS("\(Brand.name) – Info und Einstellungen", "\(Brand.name) – Info and settings", "\(Brand.name) – 信息与设置", "\(Brand.name) – 資訊與設定")
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.level = SessionController.shared.isActive
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
            : .normal
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        // 点红叉关闭时也要收掉颜色面板
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: w, queue: .main) { [weak self] _ in
            self?.closeWindow()
        }
    }

    private var isClosing = false

    private func closeWindow() {
        // window.close() 会同步发出 willCloseNotification，而观察者又调用本方法 ——
        // 之前没有防护，window 在 close() 之后才置空，于是无限递归导致闪退。
        guard !isClosing else { return }
        isClosing = true
        ColorPanelBridge.shared.dismiss()
        let w = window
        window = nil            // 先置空，回调再进来时直接返回
        w?.close()
        isClosing = false
        SessionController.shared.makeCanvasKey()
    }

    /// 会话开始/结束时调整设置窗口层级。
    /// 只有标注进行中才需要盖住冻结层；平时用普通层级，
    /// 否则 NSOpenPanel / NSColorPanel 这类系统面板会被压在设置窗口下面。
    func adaptToSession() {
        guard let w = window else { return }
        w.level = SessionController.shared.isActive
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
            : .normal
        ColorPanelBridge.shared.updateLevel(above: w.level)
    }
}
