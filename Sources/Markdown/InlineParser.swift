import Foundation

/// Markdown 行内语法解析
enum InlineParser {

    static func parse(_ text: String) -> [Inline] {
        var out: [Inline] = []
        var buffer = ""
        let chars = Array(text)
        var i = 0

        func flush() {
            if !buffer.isEmpty {
                out.append(.text(buffer))
                buffer = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            // 反斜杠转义
            if c == "\\", i + 1 < chars.count, isEscapable(chars[i + 1]) {
                buffer.append(chars[i + 1])
                i += 2
                continue
            }

            // 硬换行
            if c == "\n" {
                flush()
                out.append(.lineBreak)
                i += 1
                continue
            }

            // 图片 ![alt](url)
            if c == "!", i + 1 < chars.count, chars[i + 1] == "[" {
                if let link = parseLinkLike(chars, bracketIndex: i + 1) {
                    flush()
                    out.append(.image(alt: Inline.flatten(parse(link.text)), url: link.url))
                    i = link.end
                    continue
                }
            }

            // 链接 [text](url)
            if c == "[", let link = parseLinkLike(chars, bracketIndex: i) {
                flush()
                out.append(.link(text: parse(link.text), url: link.url))
                i = link.end
                continue
            }

            // <https://...> 自动链接
            if c == "<", let auto = parseAutolink(chars, at: i) {
                flush()
                out.append(.link(text: [.text(auto.url)], url: auto.url))
                i = auto.end
                continue
            }

            // 行内代码
            if c == "`", let span = parseCodeSpan(chars, at: i) {
                flush()
                out.append(.code(span.code))
                i = span.end
                continue
            }

            // 加粗 / 斜体
            if c == "*" || c == "_", let em = parseEmphasis(chars, at: i) {
                flush()
                out.append(em.node)
                i = em.end
                continue
            }

            // 删除线
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~",
               let del = parseStrikethrough(chars, at: i) {
                flush()
                out.append(del.node)
                i = del.end
                continue
            }

            // 裸 URL
            if let url = parseBareURL(chars, at: i) {
                flush()
                out.append(.link(text: [.text(url.url)], url: url.url))
                i = url.end
                continue
            }

            buffer.append(c)
            i += 1
        }

        flush()
        return out
    }

    // MARK: - 行内代码

    private static func parseCodeSpan(_ chars: [Character], at start: Int) -> (code: String, end: Int)? {
        var len = 0
        var p = start
        while p < chars.count, chars[p] == "`" { len += 1; p += 1 }

        var q = p
        while q < chars.count {
            guard chars[q] == "`" else { q += 1; continue }
            var run = 0
            var r = q
            while r < chars.count, chars[r] == "`" { run += 1; r += 1 }
            if run == len {
                var content = String(chars[p..<q])
                // 首尾各一个空格且内容非全空格时，按 CommonMark 去掉这对空格
                if content.count >= 2, content.hasPrefix(" "), content.hasSuffix(" "),
                   !content.allSatisfy({ $0 == " " }) {
                    content = String(content.dropFirst().dropLast())
                }
                return (content.replacingOccurrences(of: "\n", with: " "), r)
            }
            q = r
        }
        return nil
    }

    // MARK: - 强调

    private static func parseEmphasis(_ chars: [Character], at start: Int) -> (node: Inline, end: Int)? {
        let marker = chars[start]

        var len = 0
        var p = start
        while p < chars.count, chars[p] == marker { len += 1; p += 1 }

        // `_` 需要左侧边界不是字母数字，避免 foo_bar_baz 被误判
        if marker == "_", start > 0, isWordChar(chars[start - 1]) { return nil }

        for tryLen in stride(from: min(len, 3), through: 1, by: -1) {
            guard let close = findClosingRun(chars, from: p, marker: marker, length: tryLen) else { continue }
            let inner = String(chars[(start + tryLen)..<close])
            if inner.isEmpty { continue }

            // `_` 的右边界同样要求非字母数字
            if marker == "_" {
                let after = close + tryLen
                if after < chars.count, isWordChar(chars[after]) { continue }
            }

            let children = parse(inner)
            let end = close + tryLen
            switch tryLen {
            case 1:  return (.emph(children), end)
            case 2:  return (.strong(children), end)
            default: return (.strong([.emph(children)]), end)
            }
        }
        return nil
    }

    private static func findClosingRun(_ chars: [Character], from start: Int,
                                      marker: Character, length: Int) -> Int? {
        var q = start
        while q < chars.count {
            if chars[q] == "\\" { q += 2; continue }
            guard chars[q] == marker else { q += 1; continue }
            var run = 0
            var r = q
            while r < chars.count, chars[r] == marker { run += 1; r += 1 }
            if run >= length { return q }
            q = r
        }
        return nil
    }

    // MARK: - 删除线

    private static func parseStrikethrough(_ chars: [Character], at start: Int) -> (node: Inline, end: Int)? {
        var q = start + 2
        while q + 1 < chars.count {
            if chars[q] == "~", chars[q + 1] == "~" {
                let inner = String(chars[(start + 2)..<q])
                guard !inner.isEmpty else { return nil }
                return (.strikethrough(parse(inner)), q + 2)
            }
            q += 1
        }
        return nil
    }

    // MARK: - 链接

    private static func parseLinkLike(_ chars: [Character], bracketIndex: Int) -> (text: String, url: String, end: Int)? {
        guard bracketIndex < chars.count, chars[bracketIndex] == "[" else { return nil }

        // 找到配对的 ]
        var depth = 0
        var j = bracketIndex
        var textEnd = -1
        while j < chars.count {
            let c = chars[j]
            if c == "\\" { j += 2; continue }
            if c == "[" { depth += 1 }
            else if c == "]" {
                depth -= 1
                if depth == 0 { textEnd = j; break }
            }
            j += 1
        }
        guard textEnd > bracketIndex else { return nil }

        let k = textEnd + 1
        guard k < chars.count, chars[k] == "(" else { return nil }

        // 扫描到配对的 )
        var inner = ""
        var q = k + 1
        var pdepth = 1
        var quote: Character?
        while q < chars.count {
            let c = chars[q]
            if let activeQuote = quote {
                if c == activeQuote { quote = nil }
                inner.append(c); q += 1; continue
            }
            if c == "\\", q + 1 < chars.count {
                inner.append(c); inner.append(chars[q + 1]); q += 2; continue
            }
            if c == "\"" || c == "'" { quote = c; inner.append(c); q += 1; continue }
            if c == "(" { pdepth += 1; inner.append(c); q += 1; continue }
            if c == ")" {
                pdepth -= 1
                if pdepth == 0 { break }
                inner.append(c); q += 1; continue
            }
            inner.append(c); q += 1
        }
        guard pdepth == 0 else { return nil }

        var url = inner.trimmingCharacters(in: .whitespaces)
        // 去掉可选的 "title"
        if let r = url.range(of: "\\s+[\"'][^\"']*[\"']\\s*$", options: .regularExpression) {
            url = String(url[url.startIndex..<r.lowerBound])
        }
        if url.hasPrefix("<"), url.hasSuffix(">") {
            url = String(url.dropFirst().dropLast())
        }

        let text = String(chars[(bracketIndex + 1)..<textEnd])
        return (text, unescape(url), q + 1)
    }

    private static func parseAutolink(_ chars: [Character], at start: Int) -> (url: String, end: Int)? {
        var q = start + 1
        var buf = ""
        while q < chars.count, chars[q] != ">", chars[q] != " ", chars[q] != "\n" {
            buf.append(chars[q]); q += 1
        }
        guard q < chars.count, chars[q] == ">" else { return nil }
        guard buf.hasPrefix("http://") || buf.hasPrefix("https://") || buf.hasPrefix("mailto:") else { return nil }
        return (buf, q + 1)
    }

    private static func parseBareURL(_ chars: [Character], at start: Int) -> (url: String, end: Int)? {
        let prefix = "https://"
        let plen = prefix.count
        guard start + plen <= chars.count else { return nil }
        guard String(chars[start..<(start + plen)]) == prefix else { return nil }
        if start > 0 {
            let prev = chars[start - 1]
            if isWordChar(prev) || prev == "/" || prev == "@" || prev == "." { return nil }
        }

        let stoppers = "，。；：！？（）【】「」《》、\"'“”‘’"
        var buf = ""
        var q = start
        while q < chars.count {
            let c = chars[q]
            if c.isWhitespace || stoppers.contains(c) { break }
            buf.append(c); q += 1
        }
        while let last = buf.last, ".,;:!?)]}>".contains(last) {
            buf.removeLast(); q -= 1
        }
        guard buf.count > plen + 1 else { return nil }
        return (buf, q)
    }

    // MARK: - 工具

    private static func isEscapable(_ c: Character) -> Bool {
        "\\`*_{}[]()#+-.!~>|\"$".contains(c)
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter && c.isASCII || (c.isNumber && c.isASCII)
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        return s.replacingOccurrences(
            of: "\\\\([\\\\`*_{}\\[\\]()#+\\-.!~>|\"$])",
            with: "$1",
            options: .regularExpression
        )
    }
}
