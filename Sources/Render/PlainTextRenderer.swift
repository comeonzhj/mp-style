import Foundation

/// 把 Markdown 降级成纯文本，作为剪贴板的 `public.utf8-plain-text` 回退内容。
/// 粘贴到不支持 HTML 的地方时至少能得到可读的文本。
enum PlainTextRenderer {

    static func render(_ markdown: String) -> String {
        let nodes = BlockParser.parse(markdown)
        return blocks(nodes, indent: 0)
    }

    private static func blocks(_ nodes: [MDNode], indent: Int) -> String {
        var lines: [String] = []
        let pad = String(repeating: " ", count: indent)

        for node in nodes {
            switch node {
            case .heading(let level, let text):
                lines.append(pad + Inline.flatten(InlineParser.parse(text)))
                if level <= 2 {
                    lines.append(pad + String(repeating: "─", count: 24))
                }

            case .paragraph(let text):
                lines.append(pad + Inline.flatten(InlineParser.parse(text)))

            case .list(let ordered, let start, let items):
                for (index, item) in items.enumerated() {
                    let bullet = ordered ? "\(start + index)." : "•"
                    let box: String
                    switch item.checked {
                    case .some(true):  box = "[x] "
                    case .some(false): box = "[ ] "
                    case .none:        box = ""
                    }
                    lines.append(pad + "\(bullet) \(box)\(Inline.flatten(InlineParser.parse(item.text)))")
                    if !item.children.isEmpty {
                        lines.append(blocks(item.children, indent: indent + 2))
                    }
                }

            case .blockquote(let children):
                let inner = blocks(children, indent: indent + 2)
                lines.append(inner.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "\(pad)> \($0.trimmingCharacters(in: .whitespaces))" }
                    .joined(separator: "\n"))

            case .codeBlock(let code, _):
                lines.append(code.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "\(pad)    \($0)" }
                    .joined(separator: "\n"))

            case .table(let headers, _, let rows):
                lines.append(pad + headers.joined(separator: " | "))
                for row in rows {
                    lines.append(pad + row.joined(separator: " | "))
                }

            case .thematicBreak:
                lines.append(pad + String(repeating: "-", count: 40))
            }
        }

        return lines.joined(separator: "\n\n")
    }
}
