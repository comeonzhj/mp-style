import AppKit

/// 剪贴板导出。
///
/// 微信公众号编辑器读取的是剪贴板里的 `public.html`，并会丢弃 `<style>` 与 class，
/// 因此必须保证写进去的 HTML 已经完全内联。这里同时写入纯文本作为降级回退。
enum ClipboardExporter {

    /// 写入剪贴板。返回是否成功。
    @discardableResult
    static func copy(html: String, plainText: String) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()

        // 包一层完整文档：部分富文本编辑器更认完整 HTML 文档而不是裸片段
        let document = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head><meta charset="utf-8"></head>
        <body style="margin: 0; padding: 0;">\(html)</body>
        </html>
        """

        board.declareTypes([.html, .string], owner: nil)
        let htmlOK = board.setString(document, forType: .html)
        board.setString(plainText, forType: .string)
        return htmlOK
    }

    /// 当前剪贴板里是否已经有 HTML
    static var hasHTML: Bool {
        NSPasteboard.general.availableType(from: [.html]) != nil
    }
}
