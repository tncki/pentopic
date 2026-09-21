import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 捕捉历史存储
//
// 每次结束捕捉都存一份 PNG 到应用支持目录，并只保留最近 N 张。
// 存在的理由：截图存进文件夹后想找回上一张，得去访达里翻 —— 这个流程太慢了。

struct HistoryEntry: Identifiable, Hashable {
    let id: String            // 文件名
    let url: URL
    let date: Date
    let pixelSize: CGSize

    var title: String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm:ss"
        return df.string(from: date)
    }
    var detail: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }

    static func == (a: HistoryEntry, b: HistoryEntry) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum CaptureHistory {

    /// 缩略图缓存 —— 每次开窗重新解码 20 张大图太慢
    private static var thumbCache: [String: NSImage] = [:]

    /// 覆盖存储位置。
    ///
    /// 自检必须设置它：开发沙箱只允许写工作区，`~/Library/Application Support` 会被拒绝，
    /// 于是所有历史相关的用例都会"静默失败"（`record` 返回 nil）而不是报错。
    /// 正式运行时为 nil，走标准的 Application Support 路径。
    static var directoryOverride: URL?

    static var directory: URL {
        if let o = directoryOverride {
            try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
            return o
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let d = base.appendingPathComponent(Brand.name, isDirectory: true)
                   .appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    /// 存一张。返回新条目；失败返回 nil（历史不该影响主流程，所以失败是静默的）。
    @discardableResult
    static func record(_ image: CGImage) -> HistoryEntry? {
        guard Prefs.historyEnabled, Prefs.historyLimit > 0 else { return nil }
        let url = directory.appendingPathComponent("\(stamp.string(from: Date())).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        prune()
        return HistoryEntry(id: url.lastPathComponent, url: url, date: Date(),
                            pixelSize: CGSize(width: image.width, height: image.height))
    }

    /// 按时间倒序列出
    static func entries() -> [HistoryEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasSuffix(".png") }.compactMap { name -> HistoryEntry? in
            let url = directory.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let date = attrs[.creationDate] as? Date else { return nil }
            // 只读文件头拿尺寸，不解码整张图
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return HistoryEntry(id: name, url: url, date: date,
                                pixelSize: CGSize(width: w, height: h))
        }
        .sorted { $0.date > $1.date }
    }

    /// 缩略图（带内存缓存）
    static func thumbnail(for entry: HistoryEntry, maxPixel: CGFloat = 480) -> NSImage? {
        if let c = thumbCache[entry.id] { return c }
        guard let src = CGImageSourceCreateWithURL(entry.url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache[entry.id] = img
        return img
    }

    static func image(for entry: HistoryEntry) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(entry.url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func delete(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        thumbCache[entry.id] = nil
    }

    static func clear() {
        for e in entries() { delete(e) }
        thumbCache.removeAll()
    }

    /// 超出上限的旧文件删掉
    static func prune() {
        let limit = max(1, Prefs.historyLimit)
        let all = entries()
        guard all.count > limit else { return }
        for e in all.dropFirst(limit) { delete(e) }
    }

    /// 目录是否真的可写。写失败时 `record` 只能静默返回 nil，
    /// 那就成了一个不报错也不工作的功能 —— 所以给界面一个显式的检查。
    static var isWritable: Bool {
        let p = directory.appendingPathComponent(".write-probe")
        let ok = (try? Data([0]).write(to: p)) != nil
        try? FileManager.default.removeItem(at: p)
        return ok
    }

    static func totalBytes() -> Int64 {
        entries().reduce(0) { sum, e in
            let n = (try? FileManager.default.attributesOfItem(atPath: e.url.path)[.size] as? Int64) ?? 0
            return sum + (n ?? 0)
        }
    }
}

// MARK: - 历史窗口的数据模型

final class HistoryModel: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    @Published var selected: String?

    func reload() { entries = CaptureHistory.entries() }
}

// MARK: - 历史窗口

final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()

    private var window: NSWindow?
    private var isClosing = false
    let model = HistoryModel()

    func show() {
        model.reload()
        if window == nil { build() }
        guard let w = window else { return }
        // 会话进行中时浮在遮罩之上，否则用普通层级
        w.level = SessionController.shared.isActive
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
            : .normal
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let view = HistoryView(model: model, controller: self)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = LS("Aufnahmeverlauf", "Capture history", "捕捉历史", "捕捉歷史")
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.minSize = NSSize(width: 520, height: 380)
        w.delegate = self
        w.center()
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        isClosing = true
        window?.delegate = nil
        window = nil
        isClosing = false
    }

    // MARK: 条目操作

    func copySelected() {
        guard let e = current(), let img = CaptureHistory.image(for: e) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))])
        SessionController.shared.flashStatus(LS("In die Zwischenablage kopiert", "Copied to clipboard",
                                                "已复制到剪贴板", "已複製到剪貼簿"))
    }

    func saveSelected() {
        guard let e = current(), let img = CaptureHistory.image(for: e) else { return }
        let panel = NSSavePanel()
        panel.title = LS("Speichern unter …", "Save as …", "另存为 …", "另存新檔 …")
        panel.nameFieldStringValue = Exporter.defaultName(format: .png)
        panel.allowedContentTypes = ExportFormat.allCases.map { $0.utType }
        panel.level = window?.level ?? .normal
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ext = url.pathExtension.lowercased()
        let fmt = ExportFormat(rawValue: ext) ?? (ext == "jpeg" ? .jpg : .png)
        Exporter.write(img, to: url, format: fmt)
    }

    func revealSelected() {
        guard let e = current() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([e.url])
    }

    func deleteSelected() {
        guard let e = current() else { return }
        CaptureHistory.delete(e)
        model.selected = nil
        model.reload()
    }

    func clearAll() {
        let alert = NSAlert()
        alert.messageText = LS("Gesamten Verlauf löschen?", "Delete the whole history?",
                               "清空全部捕捉历史？", "清空全部捕捉歷史？")
        alert.informativeText = LS("Die Dateien werden endgültig gelöscht.",
                                   "The files will be deleted permanently.",
                                   "这些文件会被永久删除。", "這些檔案會被永久刪除。")
        alert.addButton(withTitle: LS("Löschen", "Delete", "删除", "刪除"))
        alert.addButton(withTitle: LS("Abbrechen", "Cancel", "取消", "取消"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        CaptureHistory.clear()
        model.selected = nil
        model.reload()
    }

    /// 把历史里的这一张重新丢回标注会话继续编辑
    func reopenInSession() {
        guard let e = current(), let img = CaptureHistory.image(for: e) else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let pointW = CGFloat(img.width) / screen.backingScaleFactor
        let pointH = CGFloat(img.height) / screen.backingScaleFactor
        // 放在屏幕中央，尺寸按图像比例（不放大超过屏幕）
        let fit = min(1, min(screen.frame.width / pointW, screen.frame.height / pointH))
        let w = pointW * fit, h = pointH * fit
        let rect = CGRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h)
        let entryID = e.id
        window?.orderOut(nil); window = nil
        SessionController.shared.startSession(withImage: img, rect: rect) {
            SessionController.shared.flashStatus(LS("Aus dem Verlauf geöffnet: \(entryID)",
                                                    "Opened from history: \(entryID)",
                                                    "已从历史打开：\(entryID)",
                                                    "已從歷史開啟：\(entryID)"))
        }
    }

    private func current() -> HistoryEntry? {
        guard let id = model.selected else { return nil }
        return model.entries.first { $0.id == id }
    }
}

// MARK: - 历史窗口界面

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let controller: HistoryWindowController

    private let cols = [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if !CaptureHistory.isWritable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LS("Der Verlaufsordner ist nicht beschreibbar",
                                "The history folder is not writable",
                                "历史目录不可写", "歷史目錄不可寫"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(CaptureHistory.directory.path)
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.14))
                Divider()
            }
            if model.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40)).foregroundColor(.secondary)
                    Text(LS("Noch keine Aufnahmen", "No captures yet", "还没有捕捉记录", "還沒有捕捉記錄"))
                        .foregroundColor(.secondary)
                    Text(LS("Beendete Aufnahmen erscheinen automatisch hier.",
                            "Finished captures appear here automatically.",
                            "每次结束捕捉后会自动出现在这里。",
                            "每次結束捕捉後會自動出現在這裡。"))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(model.entries) { e in
                            card(e)
                        }
                    }
                    .padding(14)
                }
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private func card(_ e: HistoryEntry) -> some View {
        let isSel = model.selected == e.id
        return VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                if let t = CaptureHistory.thumbnail(for: e) {
                    Image(nsImage: t)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                }
            }
            .frame(height: 108)
            Text(e.title).font(.system(size: 11, weight: .medium))
            Text(e.detail).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSel ? Color.accentColor.opacity(0.22) : Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSel ? Color.accentColor : Color.black.opacity(0.16), lineWidth: isSel ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selected = e.id; controller.reopenInSession() }
        .onTapGesture { model.selected = e.id }
        .contextMenu {
            Button(LS("Im Editor öffnen", "Open in editor", "在标注中打开", "在標註中開啟")) {
                model.selected = e.id; controller.reopenInSession()
            }
            Divider()
            Button(LS("Kopieren", "Copy", "复制到剪贴板", "複製到剪貼簿")) {
                model.selected = e.id; controller.copySelected()
            }
            Button(LS("Speichern unter …", "Save as …", "另存为 …", "另存新檔 …")) {
                model.selected = e.id; controller.saveSelected()
            }
            Button(LS("Im Finder zeigen", "Reveal in Finder", "在访达中显示", "在 Finder 中顯示")) {
                model.selected = e.id; controller.revealSelected()
            }
            Divider()
            Button(LS("Löschen", "Delete", "删除", "刪除")) {
                model.selected = e.id; controller.deleteSelected()
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(LS("Im Editor öffnen", "Open in editor", "在标注中打开", "在標註中開啟")) {
                controller.reopenInSession()
            }
            .disabled(model.selected == nil)
            Button(LS("Kopieren", "Copy", "复制", "複製")) { controller.copySelected() }
                .disabled(model.selected == nil)
            Button(LS("Speichern unter …", "Save as …", "另存为 …", "另存新檔 …")) { controller.saveSelected() }
                .disabled(model.selected == nil)
            Button(LS("Im Finder zeigen", "Reveal in Finder", "在访达中显示", "在 Finder 中顯示")) {
                controller.revealSelected()
            }
            .disabled(model.selected == nil)

            Divider().frame(height: 18)

            Text(LS("Behalten:", "Keep:", "保留：", "保留：") + " \(Prefs.historyLimit)")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Text(byteText).font(.system(size: 11)).foregroundColor(.secondary)

            Spacer()

            Button(LS("Verlauf leeren", "Clear history", "清空历史", "清空歷史")) {
                controller.clearAll()
            }
            .disabled(model.entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var byteText: String {
        let b = CaptureHistory.totalBytes()
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
