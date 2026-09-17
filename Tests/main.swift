import Foundation

// 命令行渲染校验工具。
// 用法：render-cli <输入.md> [输出.html]
// 会把 Markdown 渲染成公众号内联样式 HTML，并输出一份可直接用浏览器打开的完整页面。

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("用法: render-cli <输入.md> [输出.html]\n".data(using: .utf8)!)
    exit(2)
}

let inputPath = arguments[1]
let outputPath = arguments.count >= 3 ? arguments[2] : nil

guard let markdown = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    FileHandle.standardError.write("无法读取 \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

let config = ThemeConfig()
let renderer = HTMLRenderer(config: config)
let fragment = renderer.render(markdown)
let page = renderer.renderStandalonePage(markdown)

if let outputPath {
    let url = URL(fileURLWithPath: outputPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    do {
        try page.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write("写入失败: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - 结构统计

func count(_ pattern: String, in text: String) -> Int {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
    return re.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
}

/// 返回正则第一个捕获组的所有匹配
func captures(_ pattern: String, in text: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
        match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ""
    }
}

let nodes = BlockParser.parse(markdown)
var headingCounts: [Int: Int] = [:]
var paragraphCount = 0, listCount = 0, quoteCount = 0, codeCount = 0, tableCount = 0, ruleCount = 0
var customCounts: [CustomBlockKind: Int] = [:]

func walk(_ list: [MDNode]) {
    for node in list {
        switch node {
        case .heading(let level, _):  headingCounts[level, default: 0] += 1
        case .paragraph:              paragraphCount += 1
        case .list(_, _, let items):
            listCount += 1
            for item in items { walk(item.children) }
        case .blockquote(let children):
            quoteCount += 1
            walk(children)
        case .codeBlock:              codeCount += 1
        case .table:                  tableCount += 1
        case .thematicBreak:          ruleCount += 1
        case .customBlock(let kind, _): customCounts[kind, default: 0] += 1
        }
    }
}
walk(nodes)

let headingSummary = (1...6).compactMap { level -> String? in
    guard let n = headingCounts[level] else { return nil }
    return "h\(level)=\(n)"
}.joined(separator: " ")

let customSummary = CustomBlockKind.allCases.compactMap { kind -> String? in
    guard let n = customCounts[kind] else { return nil }
    return "\(kind.rawValue)=\(n)"
}.joined(separator: " ")

print("""
── 渲染结果 ─────────────────────────────
输入        : \(inputPath)
输出        : \(outputPath ?? "(未写文件)")
正文字号    : \(ThemeConfig.cssPx(config.fontSize))
主题色      : \(config.themeColor)
加粗        : 字重 \(config.boldWeight) / 颜色 \(config.effectiveBoldColor)（\(config.boldColorMode.label)）
标题        : \(headingSummary.isEmpty ? "无" : headingSummary)
滚动块      : \(customSummary.isEmpty ? "无" : customSummary)
段落        : \(paragraphCount)
列表        : \(listCount)
引用        : \(quoteCount)
代码块      : \(codeCount)
表格        : \(tableCount)
分割线      : \(ruleCount)
HTML 长度   : \(fragment.count) 字符
""")

// MARK: - 关键规则断言

var failures: [String] = []
func expect(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

expect(fragment.contains("font-weight: 100"), "正文应为 font-weight: 100")
expect(fragment.contains("font-weight: 500"), "加粗应为 font-weight: 500")
expect(fragment.contains("#1B63F3"), "应包含默认主题色 #1B63F3")
expect(!fragment.contains("border-image"), "不应残留原文的渐变左边条")
expect(!fragment.contains("::before"), "不应使用伪元素（公众号不支持）")
expect(!fragment.contains("<style"), "不应输出 <style> 标签")
expect(!fragment.contains(" class="), "不应输出 class 属性")

// style 属性被内层双引号截断时，右引号后面会紧跟字母；正常应紧跟 > / 空格 / /
let truncated = count("style=\"[^\"]*\"[A-Za-z]", in: fragment)
expect(truncated == 0, "style 属性被内联双引号截断（\(truncated) 处）")
expect(fragment.contains("'PingFang SC'"), "字体名应使用单引号，避免截断 style 属性")

// 二级标题不得带左边框
if let h2 = fragment.range(of: "<h2 ") {
    let segment = String(fragment[h2.lowerBound...].prefix(400))
    if let close = segment.range(of: ">") {
        let style = String(segment[..<close.lowerBound])
        expect(!style.contains("border-left"), "二级标题不应有 border-left")
        expect(style.contains("#1B63F3"), "二级标题应使用主题色")
    }
} else {
    failures.append("未找到 <h2>")
}

if fragment.contains("<h3 ") {
    expect(fragment.contains("<h3 "), "应输出三级标题")
}

if fragment.contains("<ol") || fragment.contains("<ul") {
    failures.append("列表不应使用 ol/ul（公众号下序号颜色不可控）")
}
if listCount > 0 {
    expect(fragment.contains("</span>&nbsp;") || fragment.contains("☐</span>") || fragment.contains("☑</span>"),
           "列表序号 / 圆点应为真实文本节点")
}

// ── 滚动块 ────────────────────────────────────────────────
if customCounts[.longText, default: 0] > 0 {
    expect(fragment.contains("overflow-y: auto"), "长文本块应有 overflow-y: auto")
    expect(fragment.contains("-webkit-overflow-scrolling: touch"),
           "滚动块应开启 iOS 顺势滚动")
}
if customCounts[.longImage, default: 0] > 0 {
    expect(fragment.contains("max-height: \(ThemeConfig.cssPx(config.longImageMaxHeight))"),
           "长图容器应带上限高")
}
if customCounts[.moreImages, default: 0] > 0 {
    expect(fragment.contains("overflow-x: auto"), "多图组应有 overflow-x: auto")
    expect(fragment.contains("white-space: nowrap"), "多图组应禁止换行以形成横滑")
    expect(fragment.contains("display: inline-block"), "多图组的图片应水平排列")

    // inline-block 之间出现换行或空格会渲染出多余间隙，所以容器内部不能有换行
    let galleries = captures("<section style=\"[^\"]*white-space: nowrap[^\"]*\">(.*?)</section>", in: fragment)
    expect(!galleries.isEmpty, "未找到多图横滑容器")
    let broken = galleries.filter { $0.contains("\n") }.count
    expect(broken == 0, "\(broken) 个多图容器内部出现了换行")
}

// 加粗颜色可配：切成「同正文」后不应再出现主题色加粗
do {
    var alt = ThemeConfig()
    alt.boldColorMode = .custom
    alt.customBoldColor = "#D93F3F"
    let altHTML = HTMLRenderer(config: alt).render("这是**加粗**文字")
    expect(altHTML.contains("font-weight: 500"), "自定义加粗仍应保留字重设置")
    expect(altHTML.contains("#D93F3F"), "自定义加粗颜色未生效")
}
do {
    var alt = ThemeConfig()
    alt.boldWeight = 700
    alt.boldColorMode = .inherit
    let altHTML = HTMLRenderer(config: alt).render("这是**加粗**文字")
    expect(altHTML.contains("font-weight: 700"), "加粗字重未生效")
    expect(altHTML.contains("#333333"), "「同正文」模式应沿用正文颜色")
}

print("── 校验 ────────────────────────────────")
if failures.isEmpty {
    print("全部通过 ✓")
} else {
    for failure in failures { print("✗ \(failure)") }
    exit(1)
}
