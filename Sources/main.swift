// main.swift — 应用入口：菜单栏常驻小工具 + 启动按钮窗口
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var startPanel: StartButtonPanel!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        L.lang = Prefs.resolveLanguage()
        NSApp.setActivationPolicy(.accessory)

        // 标记文件触发：权限探测 / 真实启动路径下的完整自检
        if let req = SelfTest.markerRequest {
            if req.mode == "selftest" {
                SelfTest.outDirOverride = req.dir
                DispatchQueue.main.async { SelfTest.run() }
                return
            }
            SelfTest.writeProbe(to: req.dir)
            exit(0)
        }

        // 真机端到端自检模式（POFIX_SELFTEST=<目录>）
        if SelfTest.enabled {
            DispatchQueue.main.async { SelfTest.run() }
            return
        }

        buildMainMenu()
        buildStatusItem()

        startPanel = StartButtonPanel { SessionController.shared.start() }
        SessionController.shared.installStartPanel(startPanel)
        startPanel.placeAtSavedOrDefault()
        startPanel.orderFrontRegardless()

        GlobalHotKey.shared.onFire = { SessionController.shared.toggle() }
        GlobalHotKey.shared.registerCurrent()

        if Prefs.autoOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                SessionController.shared.start()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let f = SessionController.shared.toolbarPanelFrame() { Prefs.setToolbarOrigin(f.origin) }
        GlobalHotKey.shared.unregister()
    }

    // MARK: 菜单栏图标

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: Brand.name)
            button.toolTip = Brand.name
        }
        let menu = NSMenu()
        menu.addItem(withTitle: LS("Start / Fertig  (F9)", "Start / Finish  (F9)", "开始 / 完成  (F9)", "開始 / 完成  (F9)"),
                     action: #selector(menuToggle), keyEquivalent: "")
        // 窗口列表在菜单展开时才枚举 —— 提前枚举会拿到过期结果
        let windowItem = NSMenuItem(title: LS("Fenster aufnehmen", "Capture window", "捕捉窗口", "捕捉視窗"),
                                    action: nil, keyEquivalent: "")
        let windowMenu = NSMenu()
        windowMenu.delegate = self
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)

        let delayItem = NSMenuItem(title: LS("Verzögerte Aufnahme", "Delayed capture", "延时捕捉", "延時捕捉"),
                                   action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for (title, secs) in [(LS("Sofort", "Immediately", "立即", "立即"), 0),
                              ("3 s", 3), ("5 s", 5), ("10 s", 10)] {
            let it = NSMenuItem(title: title, action: #selector(menuSetDelay(_:)), keyEquivalent: "")
            it.target = self
            it.tag = secs
            it.state = (Prefs.captureDelay == secs) ? .on : .off
            delayMenu.addItem(it)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: LS("Screenshot-Ordner öffnen", "Open screenshots folder", "打开截图文件夹", "開啟截圖資料夾"),
                     action: #selector(menuOpenFolder), keyEquivalent: "")
        menu.addItem(withTitle: LS("Info und Einstellungen …", "Info and settings …", "信息与设置 …", "資訊與設定 …"),
                     action: #selector(menuSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: LS("Beenden", "Quit", "退出", "結束"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for it in menu.items { it.target = it.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        item.menu = menu
        statusItem = item
    }

    @objc private func menuToggle() { SessionController.shared.toggle() }

    /// 展开「捕捉窗口」子菜单时才去枚举窗口
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let wins = ScreenCapture.windows()
        guard !wins.isEmpty else {
            menu.addItem(withTitle: LS("Keine Fenster gefunden", "No windows found",
                                       "没有找到可捕捉的窗口", "沒有找到可捕捉的視窗"),
                         action: nil, keyEquivalent: "")
            return
        }
        for w in wins.prefix(30) {
            let it = NSMenuItem(title: "\(w.app) — \(w.title)",
                                action: #selector(menuPickWindow(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = NSNumber(value: w.id)
            menu.addItem(it)
        }
    }

    @objc private func menuPickWindow(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        SessionController.shared.captureWindow(id: CGWindowID(n.uint32Value))
    }

    @objc private func menuSetDelay(_ sender: NSMenuItem) {
        Prefs.captureDelay = sender.tag
        if let m = sender.menu {
            for it in m.items { it.state = (it.tag == sender.tag) ? .on : .off }
        }
        SessionController.shared.flashStatus(sender.tag == 0
            ? LS("Aufnahme: sofort", "Capture: immediately", "捕捉：立即", "捕捉：立即")
            : LS("Aufnahme nach \(sender.tag) s", "Capture after \(sender.tag) s",
                 "延时 \(sender.tag) 秒后捕捉", "延時 \(sender.tag) 秒後捕捉"))
    }
    @objc private func menuOpenFolder() { Exporter.openScreenshotFolder() }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuAbout() {
        let a = NSAlert()
        a.messageText = "\(Brand.name) \(Brand.version)"
        a.informativeText = LS("""
        Eine unabhängige macOS-Anwendung für Bildschirm-Annotationen.
        Inspiriert von \(Brand.upstreamName) 1.8 von \(Brand.upstreamAuthor) (\(Brand.upstreamURL)),
        steht jedoch in keiner Verbindung zu diesem Projekt und wird von ihm nicht unterstützt.

        Diese Anwendung enthält keinen Code des Originals.
        """, """
        An independent macOS screen-annotation app.
        Inspired by \(Brand.upstreamName) 1.8 by \(Brand.upstreamAuthor) (\(Brand.upstreamURL)),
        but not affiliated with or endorsed by that project.

        This application contains no code from the original.
        """, """
        一款独立的 macOS 屏幕标注应用。
        受 \(Brand.upstreamAuthor) 的 \(Brand.upstreamName) 1.8（\(Brand.upstreamURL)）启发，
        但与该原作无任何隶属或背书关系。

        本应用不包含原作的任何代码。
        """, """
        一款獨立的 macOS 螢幕標註應用。
        受 \(Brand.upstreamAuthor) 的 \(Brand.upstreamName) 1.8（\(Brand.upstreamURL)）啟發，
        但與該原作無任何隸屬或背書關係。

        本應用不包含原作的任何代碼。
        """)
        a.addButton(withTitle: "OK")
        a.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)
        a.runModal()
    }

    // MARK: 主菜单（附件程序不显示菜单栏，但快捷键仍然生效）

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: LS("Über \(Brand.name)", "About \(Brand.name)", "关于 \(Brand.name)", "關於 \(Brand.name)"),
                        action: #selector(menuAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: LS("Einstellungen …", "Settings …", "设置 …", "設定 …"),
                        action: #selector(menuSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: LS("Beenden", "Quit", "退出", "結束"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let actionItem = NSMenuItem()
        main.addItem(actionItem)
        let actionMenu = NSMenu(title: LS("Aktionen", "Actions", "操作", "操作"))
        let sc = SessionController.shared
        func add(_ title: String, _ sel: Selector, _ key: String, _ target: AnyObject) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = target
            actionMenu.addItem(it)
        }
        add(LS("Start / Fertig", "Start / Finish", "开始 / 完成", "開始 / 完成"), #selector(menuToggle), "9", self)
        actionMenu.addItem(.separator())
        add(LS("Rückgängig", "Undo", "撤销", "復原"), #selector(NSObject.menuUndoPublic), "z", sc)
        add(LS("Kopieren", "Copy", "复制", "複製"), #selector(NSObject.menuCopyPublic), "c", sc)
        add(LS("Speichern unter …", "Save as …", "另存为 …", "另存新檔 …"), #selector(NSObject.menuSavePublic), "s", sc)
        add(LS("Drucken …", "Print …", "打印 …", "列印 …"), #selector(NSObject.menuPrintPublic), "p", sc)
        add(LS("Aus Zwischenablage einfügen", "Paste from clipboard", "从剪贴板粘贴", "從剪貼簿貼上"), #selector(NSObject.menuPastePublic), "v", sc)
        actionMenu.addItem(.separator())
        add(LS("Screenshot-Ordner öffnen", "Open screenshots folder", "打开截图文件夹", "開啟截圖資料夾"), #selector(menuOpenFolder), "o", self)
        add(LS("Per E-Mail senden", "Send by e-mail", "邮件发送", "郵件傳送"), #selector(NSObject.menuMailPublic), "e", sc)
        actionItem.submenu = actionMenu

        NSApp.mainMenu = main
    }
}

// 便于菜单指向控制器
extension NSObject {
    @objc func menuUndoPublic() { SessionController.shared.undo() }
    @objc func menuCopyPublic() { Exporter.copyToClipboard(SessionController.shared.activeCanvas) }
    @objc func menuSavePublic() { Exporter.saveWithPanel(SessionController.shared.activeCanvas, screen: SessionController.shared.activeCanvas?.screen) }
    @objc func menuPrintPublic() { Exporter.print(SessionController.shared.activeCanvas) }
    @objc func menuPastePublic() { SessionController.shared.pasteFromClipboard() }
    @objc func menuMailPublic() { Exporter.composeMail(SessionController.shared.activeCanvas, openFolderFirst: false) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
