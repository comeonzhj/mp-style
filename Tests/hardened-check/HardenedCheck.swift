import AppKit
import WebKit

// 验证「强化运行时（hardened runtime）+ WKWebView + JavaScript」这条链路是否可用。
//
// 预览面板依赖 evaluateJavaScript 把渲染结果注入页面（window.__setContent）。
// 如果签名启用强化运行时之后 JIT 被拦，预览会静默变空白 —— 这个测试就是为了
// 在打包分发之前把这种情况暴露出来。
//
// 退出码 0 = 通过，1 = 失败。

final class Prober: NSObject, WKNavigationDelegate {

    private let web: WKWebView
    private var finished = false
    private var failure: String?
    private var injected = ""

    init(web: WKWebView) {
        self.web = web
        super.init()
        web.navigationDelegate = self
    }

    var done: Bool { finished }
    var error: String? { failure }
    var injectedHTML: String { injected }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let payload = "<strong style=\"color:#1B63F3\">注入成功</strong>"
        let script = "window.__setContent && window.__setContent('\(payload)')"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.failure = "evaluateJavaScript 失败: \(error.localizedDescription)"
                self.finished = true
                return
            }
            webView.evaluateJavaScript("document.getElementById('content').innerHTML") { value, error in
                if let error {
                    self.failure = "回读 DOM 失败: \(error.localizedDescription)"
                } else {
                    self.injected = (value as? String) ?? "(空)"
                }
                self.finished = true
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = "页面加载失败: \(error.localizedDescription)"
        finished = true
    }
}

@main
struct HardenedCheck {

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: web.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.orderBack(nil)

        let prober = Prober(web: web)
        web.loadHTMLString("""
        <html><body><div id="content">初始</div>
        <script>window.__setContent = function (h) {
          document.getElementById('content').innerHTML = h;
        };</script></body></html>
        """, baseURL: nil)

        let deadline = Date().addingTimeInterval(6)
        while !prober.done, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        print("强化运行时 + WKWebView 自检")
        print("  注入结果 : \(prober.injectedHTML.isEmpty ? "(未执行)" : prober.injectedHTML)")

        if !prober.done {
            print("  ✗ 超时：页面或脚本没有在 6 秒内完成")
            exit(1)
        }
        if let error = prober.error {
            print("  ✗ \(error)")
            exit(1)
        }
        guard prober.injectedHTML.contains("注入成功") else {
            print("  ✗ JavaScript 未生效，注入内容没有出现在 DOM 里")
            exit(1)
        }
        print("  ✓ JavaScript 正常执行，DOM 注入成功")
        exit(0)
    }
}
