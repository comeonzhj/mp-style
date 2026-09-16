import Foundation

/// 轻量正则辅助。正则对象在首次使用时编译并缓存，避免逐行重复编译。
enum RegexKit {

    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[pattern] { return hit }
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        cache[pattern] = re
        return re
    }
}

extension String {

    /// 返回匹配结果的分组数组，[0] 为整体匹配。不匹配返回 nil。
    func matches(_ pattern: String) -> [String]? {
        guard let re = RegexKit.regex(pattern) else { return nil }
        let ns = self as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: self, options: [], range: range) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            let r = m.range(at: idx)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// 是否匹配（不关心分组）
    func isMatching(_ pattern: String) -> Bool {
        guard let re = RegexKit.regex(pattern) else { return false }
        let ns = self as NSString
        return re.firstMatch(in: self, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }
}

/// Markdown 解析中用到的全部正则
enum RX {
    /// `## 标题`（`#` 后必须跟空白）
    static let heading  = "^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?[ \\t]*$"
    /// 标题尾部用于闭合的 `#`，仅在前面有空白时才算
    static let trailing = "^(.*?)[ \\t]+#+[ \\t]*$"
    /// 围栏代码块起始 ``` 或 ~~~
    static let fence    = "^ {0,3}(`{3,}|~{3,})[ \\t]*(\\S*)[^\\n]*$"
    /// 引用 `>`
    static let quote    = "^ {0,3}>[ ]?(.*)$"
    /// 无序列表标记
    static let bullet   = "^( *)([-+*])([ \\t]+|$)(.*)$"
    /// 有序列表标记
    static let ordered  = "^( *)(\\d{1,9})([.)])([ \\t]+|$)(.*)$"
    /// 分割线
    static let thematic = "^ {0,3}(?:(?:\\*[ \\t]*){3,}|(?:-[ \\t]*){3,}|(?:_[ \\t]*){3,})$"
    /// 表格分隔行 |---|---|
    static let tableSep = "^ {0,3}\\|?[ \\t]*:?-{1,}[-: \\t]*(?:\\|[ \\t]*:?-{1,}[-: \\t]*)*\\|?[ \\t]*$"
    /// 任务列表 - [x]
    static let task     = "^\\[([ xX])\\](?:[ \\t]+(.*))?$"
    /// 行内代码反引号串
    static let backticks = "`+"
}
