import Foundation

/// 列表标记解析结果
private struct ListMarker {
    let ordered: Bool
    let number: Int
    let indent: Int
    let markerWidth: Int
    /// 内容起始列（用于判断续行缩进）
    let contentColumn: Int
    let content: String
}

/// Markdown → 块级 AST
struct BlockParser {

    private let lines: [String]
    private var i = 0

    init(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.lines = normalized.components(separatedBy: "\n")
    }

    static func parse(_ text: String) -> [MDNode] {
        var parser = BlockParser(text)
        return parser.parseBlocks()
    }

    // MARK: - 主循环

    private mutating func parseBlocks() -> [MDNode] {
        var nodes: [MDNode] = []
        while i < lines.count {
            let line = lines[i]
            if Self.isBlank(line) { i += 1; continue }

            // 围栏代码块
            if let m = line.matches(RX.fence), m.count > 2 {
                nodes.append(parseFencedCode(fence: m[1], lang: m[2]))
                continue
            }
            // 分割线
            if line.isMatching(RX.thematic) {
                nodes.append(.thematicBreak); i += 1; continue
            }
            // 标题
            if let m = line.matches(RX.heading), m.count > 2 {
                let level = min(max(m[1].count, 1), 6)
                nodes.append(.heading(level: level, text: Self.stripTrailingHashes(m[2])))
                i += 1
                continue
            }
            // 引用
            if line.isMatching(RX.quote) {
                nodes.append(parseBlockquote()); continue
            }
            // 表格（需要探测下一行）
            if let table = parseTableIfPresent() {
                nodes.append(table); continue
            }
            // 列表
            if Self.listMarker(of: line) != nil {
                nodes.append(contentsOf: parseList()); continue
            }
            // 段落
            nodes.append(parseParagraph())
        }
        return nodes
    }

    // MARK: - 围栏代码块

    private mutating func parseFencedCode(fence: String, lang: String) -> MDNode {
        guard let marker = fence.first else { return .codeBlock(code: "", lang: nil) }
        let minLen = fence.count
        i += 1
        var body: [String] = []
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.count >= minLen, !trimmed.isEmpty, trimmed.allSatisfy({ $0 == marker }) {
                i += 1
                break
            }
            body.append(lines[i])
            i += 1
        }
        // 去掉末尾空行造成的多余换行
        while let last = body.last, Self.isBlank(last) { body.removeLast() }
        let language = lang.isEmpty ? nil : lang
        return .codeBlock(code: body.joined(separator: "\n"), lang: language)
    }

    // MARK: - 引用

    private mutating func parseBlockquote() -> MDNode {
        var inner: [String] = []
        while i < lines.count {
            let line = lines[i]
            if let m = line.matches(RX.quote), m.count > 1 {
                inner.append(m[1])
                i += 1
            } else if !Self.isBlank(line), !inner.isEmpty, !interruptsParagraph(line) {
                // 惰性续行
                inner.append(line)
                i += 1
            } else {
                break
            }
        }
        return .blockquote(BlockParser.parse(inner.joined(separator: "\n")))
    }

    // MARK: - 表格

    private mutating func parseTableIfPresent() -> MDNode? {
        guard i + 1 < lines.count else { return nil }
        let head = lines[i]
        let sep = lines[i + 1]
        guard head.contains("|"),
              sep.contains("-"),
              sep.isMatching(RX.tableSep)
        else { return nil }

        let headers = Self.splitRow(head)
        guard !headers.isEmpty else { return nil }
        let aligns = Self.splitRow(sep).map(Self.alignOf)
        i += 2

        var rows: [[String]] = []
        while i < lines.count {
            let line = lines[i]
            if Self.isBlank(line) || !line.contains("|") { break }
            if interruptsParagraph(line) { break }
            rows.append(Self.splitRow(line))
            i += 1
        }
        return .table(headers: headers, aligns: aligns, rows: rows)
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        if s.isEmpty { return [] }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignOf(_ cell: String) -> ColumnAlign {
        let t = cell.trimmingCharacters(in: .whitespaces)
        let left = t.hasPrefix(":"), right = t.hasSuffix(":")
        if left && right { return .center }
        if right { return .right }
        return .left
    }

    // MARK: - 列表

    private mutating func parseList() -> [MDNode] {
        guard let first = Self.listMarker(of: lines[i]) else { return [] }
        let baseIndent = first.indent
        let ordered = first.ordered
        var items: [ListItem] = []

        while i < lines.count {
            guard let m = Self.listMarker(of: lines[i]),
                  m.indent == baseIndent,
                  m.ordered == ordered
            else { break }

            var textParts: [String] = [m.content]
            var childLines: [String] = []
            var sawChildBlock = false
            i += 1

            // 收集本项的后续行
            while i < lines.count {
                let line = lines[i]

                if Self.isBlank(line) {
                    // 空行：向后看，若下一个非空行仍缩进到位则属于本项，否则列表结束
                    var j = i + 1
                    while j < lines.count, Self.isBlank(lines[j]) { j += 1 }
                    if j < lines.count, Self.indentWidth(lines[j]) >= m.contentColumn {
                        i = j
                        continue
                    }
                    break
                }

                let ind = Self.indentWidth(line)
                if ind >= m.contentColumn {
                    let dedented = Self.dedent(line, by: m.contentColumn)
                    if sawChildBlock {
                        childLines.append(dedented)
                    } else if interruptsParagraph(dedented) {
                        sawChildBlock = true
                        childLines.append(dedented)
                    } else {
                        textParts.append(dedented.trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                } else if ind > baseIndent {
                    // 缩进不足以视为子块，但仍比基准深 → 当作续行
                    let dedented = Self.dedent(line, by: min(ind, m.contentColumn))
                    if sawChildBlock {
                        childLines.append(dedented)
                    } else {
                        textParts.append(dedented.trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                } else {
                    break
                }
            }

            let children = childLines.isEmpty
                ? []
                : BlockParser.parse(childLines.joined(separator: "\n"))
            let raw = Self.joinLines(textParts.filter { !$0.isEmpty })
            let (text, checked) = Self.extractTaskState(raw)
            items.append(ListItem(text: text, checked: checked, children: children))
        }

        guard !items.isEmpty else { return [] }
        return [.list(ordered: ordered, start: first.number, items: items)]
    }

    private static func listMarker(of line: String) -> ListMarker? {
        if let m = line.matches(RX.bullet), m.count > 4 {
            let indent = m[1].count
            let spaces = m[3].isEmpty ? 1 : m[3].count
            return ListMarker(ordered: false, number: 0, indent: indent, markerWidth: 1,
                              contentColumn: indent + 1 + spaces, content: m[4])
        }
        if let m = line.matches(RX.ordered), m.count > 5 {
            let indent = m[1].count
            let digits = m[2]
            let number = Int(digits) ?? 1
            let delim = m[3]
            let spaces = m[4].isEmpty ? 1 : m[4].count
            let width = digits.count + delim.count
            return ListMarker(ordered: true, number: number, indent: indent, markerWidth: width,
                              contentColumn: indent + width + spaces, content: m[5])
        }
        return nil
    }

    private static func extractTaskState(_ s: String) -> (String, Bool?) {
        guard let m = s.matches(RX.task), m.count > 2 else { return (s, nil) }
        return (m[2].trimmingCharacters(in: .whitespaces), m[1].lowercased() == "x")
    }

    // MARK: - 段落

    private mutating func parseParagraph() -> MDNode {
        var parts: [String] = []
        while i < lines.count {
            let line = lines[i]
            if Self.isBlank(line) { break }
            if !parts.isEmpty {
                if interruptsParagraph(line) { break }
                // 下一行是表格分隔行 → 让表格解析接管
                if i + 1 < lines.count, line.contains("|"), lines[i + 1].isMatching(RX.tableSep) { break }
            }
            // 只去行首缩进，保留行尾空格以便识别硬换行（行尾两个空格 / 反斜杠）
            parts.append(String(line.drop(while: { $0 == " " || $0 == "\t" })))
            i += 1
        }
        return .paragraph(Self.joinLines(parts))
    }

    /// 该行是否会开启一个新的块（会打断段落）
    private func interruptsParagraph(_ line: String) -> Bool {
        if Self.isBlank(line) { return true }
        if line.isMatching(RX.fence) || line.isMatching(RX.thematic) { return true }
        if line.isMatching(RX.heading) || line.isMatching(RX.quote) { return true }
        if let m = Self.listMarker(of: line) {
            // 有序列表仅当编号为 1 时才打断段落
            return !m.ordered || m.number == 1
        }
        return false
    }

    // MARK: - 行工具

    static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func indentWidth(_ s: String) -> Int {
        var w = 0
        for ch in s {
            if ch == " " { w += 1 }
            else if ch == "\t" { w += 4 }
            else { break }
        }
        return w
    }

    static func dedent(_ line: String, by n: Int) -> String {
        var count = 0
        var idx = line.startIndex
        while idx < line.endIndex, count < n, line[idx] == " " || line[idx] == "\t" {
            idx = line.index(after: idx)
            count += 1
        }
        return String(line[idx...])
    }

    private static func stripTrailingHashes(_ s: String) -> String {
        if let m = s.matches(RX.trailing), m.count > 1 {
            return m[1].trimmingCharacters(in: .whitespaces)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 拼接软换行。
    /// - 两侧任一侧是中日韩字符时不补空格（避免"中文 中文"）
    /// - 上一行以两个空格或反斜杠结尾时，插入硬换行
    static func joinLines(_ parts: [String]) -> String {
        var out = ""
        var pendingHardBreak = false

        for raw in parts {
            let hard = raw.hasSuffix("  ") || raw.hasSuffix("\\")
            var piece = raw.trimmingCharacters(in: .whitespaces)
            if hard, piece.hasSuffix("\\") {
                piece = String(piece.dropLast()).trimmingCharacters(in: .whitespaces)
            }

            if out.isEmpty {
                out = piece
            } else if pendingHardBreak {
                out += "\n" + piece
            } else if let last = out.last, let first = piece.first, isCJK(last) || isCJK(first) {
                out += piece
            } else {
                out += " " + piece
            }
            pendingHardBreak = hard
        }
        return out
    }

    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x2E80...0x303F,      // CJK 部首 / 标点
             0x3040...0x30FF,      // 假名
             0x3400...0x4DBF,      // 扩展 A
             0x4E00...0x9FFF,      // 基本汉字
             0xF900...0xFAFF,      // 兼容汉字
             0xFE30...0xFE4F,      // 兼容标点
             0xFF00...0xFFEF,      // 全角字符
             0x20000...0x2FA1F:    // 扩展 B 及以后
            return true
        default:
            return false
        }
    }
}
