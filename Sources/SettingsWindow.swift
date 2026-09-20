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
    @Published var hotKey: Int = 101

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
        hotKey = Prefs.hotKeyCode
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
        Prefs.extraColors = extraColors
        if hotKey != Prefs.hotKeyCode {
            Prefs.hotKeyCode = hotKey
            GlobalHotKey.shared.registerCurrent()
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

                    group(LS("Ordner", "Folders", "文件夹", "資料夾")) {
                        folderRow(LS("Screenshot-Ordner", "Screenshot folder", "截图文件夹", "截圖資料夾"),
                                  path: $m.screenshotFolder) { m.screenshotFolder = $0 }
                        folderRow(LS("E-Mail-Zwischenspeicher", "E-mail temp folder", "邮件临时文件夹", "郵件臨時資料夾"),
                                  path: $m.emailFolder) { m.emailFolder = $0 }
                    }

                    group(LS("Zusätzliche Farben (max. 10)", "Additional colors (max 10)", "附加颜色（最多 10 个）", "其他顏色（最多 10 個）")) {
                        HStack(spacing: 8) {
                            ForEach(Array(m.extraColors.enumerated()), id: \.offset) { idx, hex in
                                ColorPicker("", selection: Binding(
                                    get: { Color(nsColor: NSColor(hex: hex) ?? .red) },
                                    set: { newColor in
                                        let ns = NSColor(newColor)
                                        if idx < m.extraColors.count { m.extraColors[idx] = ns.hexString }
                                    }), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 34)
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
                        Picker("", selection: $m.hotKey) {
                            Text("F9").tag(101)
                            Text("F8").tag(100)
                            Text("F10").tag(109)
                            Text("F7").tag(98)
                            Text("⌥⌘P").tag(-1)
                            Text("⌃⌥P").tag(-2)
                        }.labelsHidden().frame(width: 160)
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

    private var about: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LS("Über", "About", "关于", "關於")).font(.system(size: 12, weight: .semibold))
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
                p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)
                if p.runModal() == .OK, let u = p.url { set(u.path) }
            }
        }
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
            self?.window?.close()
            self?.window = nil
            SessionController.shared.makeCanvasKey()
        }
        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = LS("\(Brand.name) – Info und Einstellungen", "\(Brand.name) – Info and settings", "\(Brand.name) – 信息与设置", "\(Brand.name) – 資訊與設定")
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
