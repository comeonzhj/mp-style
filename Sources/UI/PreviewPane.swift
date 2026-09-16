import SwiftUI
import WebKit

/// 中间预览区。用 WKWebView 渲染「将要粘贴出去的那份 HTML」，
/// 保证预览所见即公众号所得。
struct PreviewPane: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "预览") {
                Picker("", selection: widthBinding) {
                    Text("手机").tag(375.0)
                    Text("网页").tag(677.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 116)
            }

            PreviewWebView(shell: state.shell, content: state.html)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { state.config.previewWidth },
            set: { state.config.previewWidth = $0 }
        )
    }
}

/// WKWebView 包装。
///
/// 由于正文每次输入都会变，如果每次都整页重载，滚动位置会被重置到顶部。
/// 因此拆成两条路径：
/// - `shell`（主题色 / 宽度 / 字体）变化 → 重新加载整页
/// - 仅 `content` 变化 → 通过 JS 替换 `#content` 的 innerHTML，保留滚动位置
struct PreviewWebView: NSViewRepresentable {

    let shell: String
    let content: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        context.coordinator.update(shell: shell, content: content)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(shell: shell, content: content)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {

        weak var webView: WKWebView?
        private var loadedShell: String?
        private var latestContent: String = ""
        private var pending: DispatchWorkItem?

        func update(shell: String, content: String) {
            latestContent = content
            guard let webView else { return }

            if loadedShell != shell {
                loadedShell = shell
                pending?.cancel()
                webView.loadHTMLString(shell, baseURL: nil)
                return
            }

            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let webView = self.webView else { return }
                webView.evaluateJavaScript(Self.setContentScript(self.latestContent),
                                           completionHandler: nil)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.setContentScript(latestContent),
                                       completionHandler: nil)
        }

        /// 生成注入脚本。字符串走 JSON 编码，天然处理引号与换行转义。
        private static func setContentScript(_ html: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [html], options: []),
                  let json = String(data: data, encoding: .utf8) else {
                return "window.__setContent && window.__setContent('')"
            }
            let literal = String(json.dropFirst().dropLast())
            return "window.__setContent && window.__setContent(\(literal))"
        }
    }
}
