// Exporter.swift — 保存 / 剪贴板 / 打印 / 邮件 / 自动截图
import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case png, jpg, bmp, gif, tiff, pdf
    var ext: String { rawValue }
    var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpg:  return .jpeg
        case .bmp:  return .bmp
        case .gif:  return .gif
        case .tiff: return .tiff
        case .pdf:  return .pdf
        }
    }
    var title: String { rawValue.uppercased() }
    var isLossless: Bool { self == .png || self == .tiff || self == .pdf }
}

/// 用于文件名，避免产品名里的空格/斜杠出问题
let safeBrandName: String = Brand.name
    .replacingOccurrences(of: "/", with: "-")
    .replacingOccurrences(of: ":", with: "-")

enum Exporter {

    // MARK: 取图

    static func currentImage(_ st: CanvasState?, regionOnly: Bool = true) -> CGImage? {
        guard let st else { return nil }
        let r = (regionOnly ? st.region : nil)
        return st.composeCG(region: r)
    }

    static func encode(_ cg: CGImage, as format: ExportFormat, quality: CGFloat = 0.9) -> Data? {
        if format == .pdf { return encodePDF(cg) }
        let rep = NSBitmapImageRep(cgImage: cg)
        switch format {
        case .png:  return rep.representation(using: .png, properties: [:])
        case .jpg:  return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .bmp:  return rep.representation(using: .bmp, properties: [:])
        case .gif:  return rep.representation(using: .gif, properties: [:])
        case .tiff: return rep.representation(using: .tiff, properties: [:])
        case .pdf:  return nil
        }
    }

    /// PDF 走 CGPDFContext —— NSBitmapImageRep 不支持 PDF 编码。
    /// 页面按 1pt = 1px 设尺寸，打印时再按需缩放。
    static func encodePDF(_ cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.draw(cg, in: mediaBox)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: 剪贴板

    static func copyToClipboard(_ st: CanvasState?) {
        guard let cg = currentImage(st) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        pb.writeObjects([img])
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        SessionController.shared.flashStatus(LS("In die Zwischenablage kopiert", "Copied to clipboard", "已复制到剪贴板", "已複製到剪貼簿"))
    }

    static func imageFromClipboard() -> CGImage? {
        let pb = NSPasteboard.general
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = imgs.first {
            var rect = NSRect(origin: .zero, size: first.size)
            if let cg = first.cgImage(forProposedRect: &rect, context: nil, hints: nil) { return cg }
        }
        if let data = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: data) {
            return rep.cgImage
        }
        if let data = pb.data(forType: .png), let rep = NSBitmapImageRep(data: data) {
            return rep.cgImage
        }
        return nil
    }

    // MARK: 保存

    static func saveWithPanel(_ st: CanvasState?, screen: NSScreen?) {
        guard let st, let cg = currentImage(st) else {
            SessionController.shared.flashStatus(LS("Nichts zu speichern", "Nothing to save", "没有可保存的内容", "沒有可儲存的內容"))
            return
        }
        let panel = NSSavePanel()
        panel.title = LS("Bild speichern", "Save image", "保存图片", "儲存圖片")
        panel.allowedContentTypes = ExportFormat.allCases.map { $0.utType }
        panel.nameFieldStringValue = defaultName(format: .png)
        panel.canCreateDirectories = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)

        let resp = SessionController.shared.withSuspendedOverlays { panel.runModal() }
        guard resp == .OK, let url = panel.url else { return }
        let ext = url.pathExtension.lowercased()
        let fmt = ExportFormat(rawValue: ext) ?? (ext == "jpeg" ? .jpg : .png)
        write(cg, to: url, format: fmt)
    }

    static func write(_ cg: CGImage, to url: URL, format: ExportFormat) {
        guard let data = encode(cg, as: format) else { return }
        do {
            try data.write(to: url)
            SessionController.shared.flashStatus(LS("Gespeichert: \(url.lastPathComponent)",
                                                    "Saved: \(url.lastPathComponent)",
                                                    "已保存：\(url.lastPathComponent)", "已儲存：\(url.lastPathComponent)"))
        } catch {
            Alert.error(LS("Speichern fehlgeschlagen", "Save failed", "保存失败", "儲存失敗"), error.localizedDescription)
        }
    }

    /// 按用户模板生成文件名（不含扩展名）。
    /// 占位符：{app} 应用名、{date} 年月日、{time} 时分秒、{n} 序号
    static func renderBaseName(index: Int = 0) -> String {
        var t = Prefs.filenameTemplate
        if t.trimmingCharacters(in: .whitespaces).isEmpty { t = "{app}-{date}-{time}" }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        let tf = DateFormatter(); tf.dateFormat = "HHmmss"
        let now = Date()
        t = t.replacingOccurrences(of: "{app}", with: safeBrandName)
             .replacingOccurrences(of: "{date}", with: df.string(from: now))
             .replacingOccurrences(of: "{time}", with: tf.string(from: now))
             .replacingOccurrences(of: "{n}", with: String(index))
        for bad in ["/", ":", "\\"] { t = t.replacingOccurrences(of: bad, with: "-") }
        return t.isEmpty ? safeBrandName : t
    }

    static func defaultName(format: ExportFormat) -> String {
        "\(renderBaseName()).\(format.ext)"
    }

    /// 自动命名保存到截图文件夹
    @discardableResult
    static func saveToFolder(_ st: CanvasState?, format: ExportFormat) -> URL? {
        guard let st, let cg = currentImage(st) else { return nil }
        Prefs.ensureFolders()
        let url = uniqueURL(in: Prefs.screenshotFolder, format: format)
        guard let data = encode(cg, as: format) else { return nil }
        do {
            try data.write(to: url)
            SessionController.shared.flashStatus(LS("Gespeichert: \(url.lastPathComponent)",
                                                    "Saved: \(url.lastPathComponent)",
                                                    "已保存：\(url.lastPathComponent)", "已儲存：\(url.lastPathComponent)"))
            return url
        } catch {
            Alert.error(LS("Speichern fehlgeschlagen", "Save failed", "保存失败", "儲存失敗"), error.localizedDescription)
            return nil
        }
    }

    private static func uniqueURL(in folder: URL, format: ExportFormat) -> URL {
        var n = 1
        while n <= 9999 {
            let candidate = folder.appendingPathComponent("\(renderBaseName(index: n)).\(format.ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
        return folder.appendingPathComponent("\(renderBaseName(index: Int.random(in: 1000...9999))).\(format.ext)")
    }

    /// 'Fertig' 时自动截图（整屏，忽略选区）
    static func autoScreenshot(_ st: CanvasState) {
        let fmt: ExportFormat = Prefs.autoScreenshotFormat == "jpg" ? .jpg : .png
        guard let cg = st.composeCG(region: nil) else { return }
        Prefs.ensureFolders()
        let url = uniqueURL(in: Prefs.screenshotFolder, format: fmt)
        if let data = encode(cg, as: fmt) { try? data.write(to: url) }
    }

    static func openScreenshotFolder() {
        Prefs.ensureFolders()
        NSWorkspace.shared.open(Prefs.screenshotFolder)
    }

    static func openEmailFolder() {
        Prefs.ensureFolders()
        NSWorkspace.shared.open(Prefs.emailFolder)
    }

    // MARK: 打印

    /// 构建打印任务（自检时改成输出 PDF 即可无界面验证整条打印管线）
    static func makePrintOperation(_ st: CanvasState?) -> NSPrintOperation? {
        guard let st, let cg = currentImage(st) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true

        let printable = info.imageablePageBounds.size
        let aspect = img.size.width / max(1, img.size.height)
        var w = printable.width, h = w / aspect
        if h > printable.height { h = printable.height; w = h * aspect }
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.image = img
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        return NSPrintOperation(view: view, printInfo: info)
    }

    static func print(_ st: CanvasState?) {
        guard let op = makePrintOperation(st) else { return }
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        SessionController.shared.withSuspendedOverlays { op.run() }
    }

    // MARK: 邮件

    static func composeMail(_ st: CanvasState?, openFolderFirst: Bool) {
        guard let st, let cg = currentImage(st) else { return }
        Prefs.ensureFolders()
        let fmt: ExportFormat = Prefs.autoScreenshotFormat == "jpg" ? .jpg : .png
        let url = uniqueURL(in: Prefs.emailFolder, format: fmt)
        guard let data = encode(cg, as: fmt) else { return }
        try? data.write(to: url)

        if openFolderFirst {
            openEmailFolder()
            if let svc = NSSharingService(named: .composeEmail) {
                svc.perform(withItems: [url])
            } else if let mail = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") {
                NSWorkspace.shared.open([url], withApplicationAt: mail,
                                        configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            if let svc = NSSharingService(named: .composeEmail) {
                svc.perform(withItems: [url])
            }
        }
    }
}

// MARK: - 提示框

enum Alert {
    static func error(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)
        a.runModal()
    }

    static func screenRecordingPermission() { _ = ScreenPermission.ensure() }
}

// MARK: - 屏幕录制权限引导

enum ScreenPermission {

    /// 打开「系统设置 › 隐私与安全性 › 屏幕录制」。
    ///
    /// macOS 13 起系统设置改为 ExtensionKit 架构：旧的 `com.apple.preference.security`
    /// 已降级为 legacyBundleIdentifier，实测在 macOS 26 上只会打开「通用」面板
    /// （GeneralSettings.appex 被加载），用户看到的就是"打不开隐私"。
    /// 正确标识符为 `com.apple.settings.PrivacySecurity.extension`，锚点 Privacy_ScreenCapture。
    static let settingsURLs = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    ]

    @discardableResult
    static func openSettings() -> Bool {
        for s in settingsURLs {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return true }
        }
        return false
    }

    /// 重启自身（授权后 macOS 常常要求重启进程才生效）
    static func relaunch() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// 循环引导用户授权。返回 true 表示已取得权限；用户取消返回 false。
    /// 好处：在系统设置里勾选后可以直接点「重试」，不必重启应用。
    static func ensure() -> Bool {
        guard !ScreenCapture.hasPermission else { return true }

        // 这里**故意不调用** CGRequestScreenCaptureAccess()：
        // 它在 macOS 15+ 上非阻塞，弹完系统自带的授权框后立刻返回 false，
        // 会和下面这个引导框同时出现（用户看到两个弹窗）。
        let a = NSAlert()
        a.alertStyle = .informational
        a.messageText = LS("\(Brand.name) benötigt die Berechtigung „Bildschirmaufnahme“",
                           "\(Brand.name) needs Screen Recording permission",
                           "\(Brand.name) 需要「屏幕录制」权限",
                           "\(Brand.name) 需要「螢幕錄製」權限")
        let steps = LS("""
        \(Brand.name) muss den Bildschirm einfrieren, um darauf zeichnen zu können,
        dafür ist die Berechtigung „Bildschirmaufnahme“ erforderlich.

        1. Klicken Sie unten auf „Systemeinstellungen öffnen“
        2. Aktivieren Sie unter „Datenschutz & Sicherheit › Bildschirmaufnahme“ den Schalter für \(Brand.name)
           (fehlt \(Brand.name) in der Liste, mit „+“ unten links hinzufügen)
        3. Klicken Sie danach erneut auf „Start“

        Falls es trotzdem nicht greift, verwenden Sie „Beenden und neu öffnen“.
        """, """
        \(Brand.name) must freeze the screen to annotate it, so it needs
        Screen Recording permission.

        1. Click "Open System Settings" below
        2. In "Privacy & Security › Screen Recording", switch \(Brand.name) on
           (if \(Brand.name) is not listed, add it with the "+" button at the bottom left)
        3. Then click "Start" again

        If it still does not take effect, use "Quit and Reopen".
        """, """
        \(Brand.name) 需要先冻结屏幕才能标注，所以必须获得屏幕录制权限。

        1. 点击下面的「打开系统设置」
        2. 在「隐私与安全性 › 屏幕录制」列表里把 \(Brand.name) 打开
           （如果列表里没有 \(Brand.name)，点左下角的「+」手动添加）
        3. 授权完成后，重新点一次「开始」

        如果仍然不生效，请用「退出并重新打开」。
        """, """
        \(Brand.name) 需要先凍結螢幕才能標註，所以必須獲得螢幕錄製權限。

        1. 按一下下面的「開啟系統設定」
        2. 在「隱私與安全性 › 螢幕錄製」列表裡把 \(Brand.name) 開啟
           （如果列表裡沒有 \(Brand.name)，點左下角的「+」手動加入）
        3. 授權完成後，重新按一次「開始」

        如果仍然不生效，請用「結束並重新開啟」。
        """)
        let staleHint = LS("""
        Falls \(Brand.name) in der Liste BEREITS aktiviert ist und trotzdem nicht funktioniert,
        gehört dieser Eintrag zu einer älteren Version (die App ist ad-hoc signiert, ihre
        Signatur ändert sich bei jedem Neubau). Bitte:
          · \(Brand.name) in der Liste auswählen und mit „−“ entfernen
          · anschließend erneut auf „Start“ klicken
        """, """
        If \(Brand.name) is ALREADY switched on in the list but still does not work, that entry
        belongs to an older build (this app is ad-hoc signed, so its signature changes on
        every rebuild). Please:
          - select \(Brand.name) in the list and remove it with the "-" button
          - then click Start again
        """, """
        如果列表里 \(Brand.name) 的开关【已经是打开状态】却仍然无效，说明这条授权记录绑定的是
        旧版本程序（本程序是 ad-hoc 签名，重新编译后签名指纹会变）。请：
          · 在列表里选中 \(Brand.name)，点左下角的「−」删除这条记录
          · 然后重新点一次「开始」
        """, """
        如果列表裡 \(Brand.name) 的開關【已經是開啟狀態】卻仍然無效，說明這條授權記錄綁定的是
        舊版本程式（本程式是 ad-hoc 簽名，重新編譯後簽名指紋會變）。請：
          · 在列表裡選中 \(Brand.name)，點左下角的「−」刪除這條記錄
          · 然後重新按一次「開始」
        """)
        a.informativeText = steps + "\n\n" + staleHint
        a.addButton(withTitle: LS("Systemeinstellungen öffnen", "Open System Settings", "打开系统设置", "開啟系統設定"))
        a.addButton(withTitle: LS("Beenden und neu öffnen", "Quit and Reopen", "退出并重新打开", "結束並重新開啟"))
        a.addButton(withTitle: LS("Abbrechen", "Cancel", "取消", "取消"))
        a.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 6)

        // 弹窗停留期间轮询权限：用户若在系统设置里打开开关，自动继续。
        // 必须注册到 .modalPanel —— NSAlert.runModal() 跑的是模态 run loop，
        // 而 Timer.scheduledTimer 只挂 .default 模式，那样定时器永远不会触发。
        var granted = false
        let poll = Timer(timeInterval: 0.5, repeats: true) { t in
            guard !granted, ScreenCapture.hasPermission else { return }
            granted = true
            t.invalidate()
            NSApp.stopModal(withCode: .alertFirstButtonReturn)
            a.window.orderOut(nil)
        }
        RunLoop.current.add(poll, forMode: .modalPanel)
        RunLoop.current.add(poll, forMode: .default)

        let resp = a.runModal()
        poll.invalidate()
        a.window.orderOut(nil)

        if granted || ScreenCapture.hasPermission { return true }

        // 关键：这里**绝不重新弹窗**。
        // 之前写成 continue 回到 while 顶部，导致点「打开系统设置」后弹窗立刻重开，
        // 和系统设置互相刷屏形成死循环（用户看到的现象）。
        switch resp {
        case .alertFirstButtonReturn:
            openSettings()          // 打开系统设置后关掉弹窗，让路给用户操作
        case .alertSecondButtonReturn:
            relaunch()              // macOS 缓存了旧判定时必须重启进程
        default:
            break
        }
        return false
    }
}
