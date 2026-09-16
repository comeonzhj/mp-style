import Foundation

/// 表格列对齐方式
enum ColumnAlign: String {
    case left, center, right
}

/// 列表项
struct ListItem {
    /// 该项的文本（可能为空，仅有子块）
    var text: String
    /// 任务列表勾选状态；非任务列表为 nil
    var checked: Bool?
    /// 嵌套的子块（嵌套列表、引用、代码块等）
    var children: [MDNode]
}

/// Markdown 块级 AST
indirect enum MDNode {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, start: Int, items: [ListItem])
    case blockquote([MDNode])
    case codeBlock(code: String, lang: String?)
    case table(headers: [String], aligns: [ColumnAlign], rows: [[String]])
    case thematicBreak
}

/// Markdown 行内 AST
indirect enum Inline {
    case text(String)
    case strong([Inline])
    case emph([Inline])
    case code(String)
    case strikethrough([Inline])
    case link(text: [Inline], url: String)
    case image(alt: String, url: String)
    case lineBreak
}

extension Inline {
    /// 收集行内节点里的纯文本（用于 link 文本、图片 alt 等场景）
    var plainText: String {
        switch self {
        case .text(let s):          return s
        case .code(let s):          return s
        case .lineBreak:            return " "
        case .strong(let c),
             .emph(let c),
             .strikethrough(let c): return c.map(\.plainText).joined()
        case .link(_, let url):     return url
        case .image(let alt, _):    return alt
        }
    }

    static func flatten(_ nodes: [Inline]) -> String {
        nodes.map(\.plainText).joined()
    }
}
