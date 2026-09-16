import Foundation

/// Markdown → 可直接粘贴进微信公众号编辑器的 HTML。
///
/// 输出规则：
/// - 全部样式内联在 `style` 属性里，不含任何 `<style>` / `class`
/// - 列表序号、任务勾选框都是真实文本节点（公众号不支持 `::before` / `list-style`）
/// - 结构只用 `section` / `p` / `span` / `strong` / `em` / `code` / `pre` / `table` 等公众号稳定支持的标签
struct HTMLRenderer {

    let config: ThemeConfig
    private let kit: StyleKit

    init(config: ThemeConfig = ThemeConfig()) {
        self.config = config
        self.kit = StyleKit(t: config)
    }

    /// 渲染上下文：记录当前嵌套层级，用于调整缩进与字号
    private struct Context {
        var quoteDepth = 0
        var listDepth = 0
        static let root = Context()
    }

    // MARK: - 对外接口

    /// 渲染正文 HTML（含可选外框卡片），这是会被复制到剪贴板的字符串
    func render(_ markdown: String) -> String {
        let nodes = BlockParser.parse(markdown)
        let body = renderBlocks(nodes, ctx: .root)
        if config.cardEnabled {
            return "<section style=\"\(kit.card())\">\n\(body)\n</section>"
        }
        return "<section style=\"\(kit.plainWrapper())\">\n\(body)\n</section>"
    }

    /// 渲染预览页骨架。
    ///
    /// 骨架里只包含「与主题/宽度有关」的样式，正文留空，由 `__setContent` 注入。
    /// 这样编辑正文时只需替换 `#content` 的 innerHTML，不必整页重载，滚动位置不会丢。
    /// 正文部分与 `render(_:)` 输出完全一致，保证「预览所见 = 粘贴所得」。
    func previewShell(title: String = "预览", content: String = "") -> String {
        let width = Int(config.previewWidth)
        let font = config.fontFamily.replacingOccurrences(of: "\"", with: "'")
        let inner = content.isEmpty
            ? "<div id=\"empty\">左侧粘贴 Markdown，这里会实时显示排版效果</div>"
            : content
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>
          html, body { margin: 0; padding: 0; background: #EEF0F3; }
          #stage { display: flex; justify-content: center; padding: 22px 14px 70px; }
          #page {
            width: \(width)px; max-width: 100%;
            background: #FFFFFF; border-radius: 16px;
            box-shadow: 0 10px 34px rgba(0,0,0,.10);
            overflow: hidden;
          }
          #content {
            padding: 22px 18px 44px;
            box-sizing: border-box;
            font-family: \(font);
            font-size: \(ThemeConfig.cssPx(config.fontSize));
            color: \(HexColor.normalize(config.textColor));
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word;
          }
          #content *, #content *::before, #content *::after { box-sizing: border-box; }
          #content img { max-width: 100%; }
          #content table { border-collapse: collapse; }
          #empty {
            color: #A8AFB8; font-size: 13px;
            text-align: center; padding: 90px 20px; line-height: 2;
          }
          ::-webkit-scrollbar { width: 8px; height: 8px; }
          ::-webkit-scrollbar-thumb { background: #C9CED6; border-radius: 4px; }
          ::-webkit-scrollbar-track { background: transparent; }
        </style>
        </head>
        <body>
          <div id="stage"><div id="page"><div id="content">\(inner)</div></div></div>
          <script>
            window.__setContent = function (html) {
              var el = document.getElementById('content');
              if (!el) { return; }
              el.innerHTML = html;
            };
          </script>
        </body>
        </html>
        """
    }

    /// 内容已内嵌的完整独立页面。用于命令行校验与离线查看，不参与剪贴板导出。
    func renderStandalonePage(_ markdown: String) -> String {
        previewShell(content: render(markdown))
    }

    // MARK: - 块级渲染

    private func renderBlocks(_ nodes: [MDNode], ctx: Context) -> String {
        nodes.map { renderBlock($0, ctx: ctx) }.joined(separator: "\n")
    }

    private func renderBlock(_ node: MDNode, ctx: Context) -> String {
        switch node {

        case .heading(let level, let text):
            let tag = "h\(min(max(level, 1), 6))"
            let style = kit.heading(level: min(level, 4))
            return "<\(tag) style=\"\(style)\">\(renderInlines(InlineParser.parse(text), ctx: ctx))</\(tag)>"

        case .paragraph(let text):
            let inlines = InlineParser.parse(text)
            // 整段只有一张图片时，直接输出 img，避免 p 的外边距产生双倍间距
            if inlines.count == 1, case .image = inlines[0] {
                return renderInlines(inlines, ctx: ctx)
            }
            return "<p style=\"\(kit.paragraph(inQuote: ctx.quoteDepth > 0))\">\(renderInlines(inlines, ctx: ctx))</p>"

        case .list(let ordered, let start, let items):
            return renderList(ordered: ordered, start: start, items: items, ctx: ctx)

        case .blockquote(let children):
            var inner = ctx
            inner.quoteDepth += 1
            let body = renderBlocks(children, ctx: inner)
            return "<section style=\"\(kit.blockquote(depth: ctx.quoteDepth))\">\n\(body)\n</section>"

        case .codeBlock(let code, _):
            let style = kit.codeBlock()
            return "<pre style=\"\(style)\"><code style=\"font-family: inherit; font-size: inherit; color: inherit; letter-spacing: 0;\">\(escapeHTML(code))</code></pre>"

        case .table(let headers, let aligns, let rows):
            return renderTable(headers: headers, aligns: aligns, rows: rows, ctx: ctx)

        case .thematicBreak:
            return "<section style=\"\(kit.divider())\"></section>"
        }
    }

    // MARK: - 列表

    private func renderList(ordered: Bool, start: Int, items: [ListItem], ctx: Context) -> String {
        var html: [String] = []
        for (index, item) in items.enumerated() {
            let marker = markerText(ordered: ordered, number: start + index,
                                    level: ctx.listDepth, checked: item.checked)
            var line = "<section style=\"\(kit.listItem(depth: ctx.listDepth))\">"
            line += "<span style=\"\(kit.listMarker())\">\(marker)</span>"
            if !item.text.isEmpty {
                line += "&nbsp;" + renderInlines(InlineParser.parse(item.text), ctx: ctx)
            }
            line += "</section>"
            html.append(line)

            if !item.children.isEmpty {
                var inner = ctx
                inner.listDepth += 1
                html.append(renderBlocks(item.children, ctx: inner))
            }
        }
        return html.joined(separator: "\n")
    }

    /// 生成列表标记文本。任务列表优先，其次有序 / 无序，逐层变换形式。
    private func markerText(ordered: Bool, number: Int, level: Int, checked: Bool?) -> String {
        if let done = checked {
            return done ? "☑" : "☐"
        }
        if ordered {
            switch level % 3 {
            case 0:  return "\(number)."
            case 1:  return "\(Self.alphaMarker(number))."
            default: return "\(Self.romanMarker(number))."
            }
        }
        switch level % 3 {
        case 0:  return "•"
        case 1:  return "◦"
        default: return "▪"
        }
    }

    private static func alphaMarker(_ n: Int) -> String {
        guard n > 0 else { return "a" }
        var result = ""
        var value = n
        while value > 0 {
            let rem = (value - 1) % 26
            result = String(UnicodeScalar(UInt8(97 + rem))) + result
            value = (value - 1) / 26
        }
        return result
    }

    private static func romanMarker(_ n: Int) -> String {
        guard n > 0, n < 4000 else { return "\(n)" }
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
            (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var value = n
        var out = ""
        for (unit, symbol) in table {
            while value >= unit {
                out += symbol
                value -= unit
            }
        }
        return out
    }

    // MARK: - 表格

    private func renderTable(headers: [String], aligns: [ColumnAlign],
                             rows: [[String]], ctx: Context) -> String {
        func align(_ index: Int) -> ColumnAlign {
            index < aligns.count ? aligns[index] : .left
        }

        var head = "<thead><tr>"
        for (index, cell) in headers.enumerated() {
            head += "<th style=\"\(kit.tableHeaderCell(align: align(index)))\">\(renderInlines(InlineParser.parse(cell), ctx: ctx))</th>"
        }
        head += "</tr></thead>"

        var body = "<tbody>"
        for row in rows {
            body += "<tr>"
            for index in 0..<headers.count {
                let cell = index < row.count ? row[index] : ""
                body += "<td style=\"\(kit.tableCell(align: align(index)))\">\(renderInlines(InlineParser.parse(cell), ctx: ctx))</td>"
            }
            body += "</tr>"
        }
        body += "</tbody>"

        return "<section style=\"\(kit.tableWrapper())\"><table style=\"\(kit.table())\">\(head)\(body)</table></section>"
    }

    // MARK: - 行内渲染

    private func renderInlines(_ nodes: [Inline], ctx: Context) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let s):
                return escapeHTML(s)
            case .strong(let children):
                return "<strong style=\"\(kit.strong())\">\(renderInlines(children, ctx: ctx))</strong>"
            case .emph(let children):
                return "<em style=\"\(kit.emphasis())\">\(renderInlines(children, ctx: ctx))</em>"
            case .code(let s):
                return "<code style=\"\(kit.inlineCode())\">\(escapeHTML(s))</code>"
            case .strikethrough(let children):
                return "<span style=\"\(kit.strikethrough())\">\(renderInlines(children, ctx: ctx))</span>"
            case .link(let text, let url):
                return "<a href=\"\(escapeAttribute(url))\" style=\"\(kit.link())\">\(renderInlines(text, ctx: ctx))</a>"
            case .image(let alt, let url):
                return "<img src=\"\(escapeAttribute(url))\" alt=\"\(escapeAttribute(alt))\" style=\"\(kit.image())\">"
            case .lineBreak:
                return "<br>"
            }
        }.joined()
    }

    // MARK: - 转义

    func escapeHTML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default:  out.append(ch)
            }
        }
        return out
    }

    func escapeAttribute(_ s: String) -> String {
        escapeHTML(s)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
