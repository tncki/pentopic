import AppKit
import WebKit

// MARK: - 应用内使用手册
//
// 手册由 Tools/md2html.py 在构建时从 HELP.md 转成单文件 HTML，打进 .app。
// 用 WKWebView 就地显示而不是丢给浏览器：帮助是应用的一部分，
// 跳出去会打断正在做的事。
//
// 只用系统框架（WebKit），仍然零第三方依赖。

final class HelpWindowController: NSObject, NSWindowDelegate {

    static let shared = HelpWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var isClosing = false

    func show() {
        if window == nil { build() }
        guard let w = window else { return }
        // 会话进行中时浮在冻结遮罩之上，否则用普通层级
        w.level = SessionController.shared.isActive
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
            : .normal
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = LS("PentoPic Handbuch", "PentoPic Manual", "PentoPic 使用手册", "PentoPic 使用手冊")
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 480, height: 360)
        w.delegate = self
        w.center()

        let config = WKWebViewConfiguration()
        // 手册是本地静态文件，不需要脚本；关掉更安全
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: w.contentView?.bounds ?? .zero, configuration: config)
        web.autoresizingMask = [.width, .height]
        w.contentView = web

        // 手册里的相对链接（指向 README.md 等）在应用内打不开，挡住它们，
        // 免得用户点了没反应还以为卡住；外链交给系统浏览器。
        web.navigationDelegate = self

        if let url = Bundle.main.url(forResource: "Help", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let msg = LS("Das Handbuch wurde beim Build nicht mitgeliefert.",
                         "The manual was not bundled at build time.",
                         "使用手册没有随构建打包进来。",
                         "使用手冊沒有隨建置打包進來。")
            web.loadHTMLString(
                "<meta charset=\"utf-8\"><body style=\"font:15px -apple-system;padding:40px\">"
                + "<h2>\\(msg)</h2>"
                + "<p style=\"color:#888\">HELP.md → Tools/md2html.py → Resources/Help.html</p>",
                baseURL: nil)
        }

        window = w
        webView = web
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        isClosing = true
        window?.delegate = nil
        window = nil
        webView = nil
        isClosing = false
    }
}

extension HelpWindowController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        // 本地文件与锚点跳转放行
        if url.isFileURL {
            decisionHandler(.allow); return
        }
        // 外链（如 GitHub）交给系统浏览器，应用本身不发起网络请求
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
