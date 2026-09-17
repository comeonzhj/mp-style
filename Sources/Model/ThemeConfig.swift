import Foundation

/// 标题颜色的取值方式
enum HeadingColorMode: String, Codable, CaseIterable, Identifiable {
    /// 跟随主题色
    case theme
    /// 参考文章原样的深色 #1D1D1F
    case dark
    /// 独立指定颜色
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .theme:  return "主题色"
        case .dark:   return "深色"
        case .custom: return "自定义"
        }
    }
}

/// 加粗文本的颜色取值方式
enum BoldColorMode: String, Codable, CaseIterable, Identifiable {
    /// 跟随主题色（默认）
    case theme
    /// 只加粗、不变色，沿用正文颜色
    case inherit
    /// 独立指定颜色
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .theme:   return "主题色"
        case .inherit: return "同正文"
        case .custom:  return "自定义"
        }
    }
}

/// 全部排版参数。纯 Foundation 模型，不依赖任何 UI 框架，
/// 因此命令行渲染测试可以直接复用。
struct ThemeConfig: Codable, Equatable {

    // MARK: - 主题色

    /// 主题色，默认 #1B63F3
    var themeColor: String = "#1B63F3"
    /// 正文颜色
    var textColor: String = "#333333"
    /// 次级文字颜色（引用、图注等）
    var secondaryTextColor: String = "#888888"
    /// 标题颜色取值方式
    var headingColorMode: HeadingColorMode = .theme
    /// headingColorMode == .custom 时生效
    var customHeadingColor: String = "#1D1D1F"

    // MARK: - 正文

    var fontFamily: String = ThemeConfig.defaultFontFamily
    var monoFamily: String = ThemeConfig.defaultMonoFamily
    /// 正文字号（px）
    var fontSize: Double = 15
    /// 正文字重。参考排版为细体，默认 100
    var bodyWeight: Int = 100
    /// 加粗字重，默认 500
    var boldWeight: Int = 500
    /// 加粗文本的颜色取值方式
    var boldColorMode: BoldColorMode = .theme
    /// boldColorMode == .custom 时生效
    var customBoldColor: String = "#1B63F3"
    var lineHeight: Double = 1.8
    /// 字距（em）
    var letterSpacing: Double = 0.1
    /// 段间距（em）
    var paragraphSpacing: Double = 1.2
    var textAlignJustify: Bool = true

    // MARK: - 标题

    var h1Scale: Double = 1.60
    var h2Scale: Double = 1.333
    var h3Scale: Double = 1.13
    var h4Scale: Double = 1.00
    var headingWeight: Int = 600
    var h1Top: Double = 1.9
    var h1Bottom: Double = 1.0
    /// 二级标题上边距（em）
    var h2Top: Double = 1.8
    /// 二级标题下边距（em）
    var h2Bottom: Double = 1.0
    /// 二级标题行高
    var h2LineHeight: Double = 1.60
    /// 三级标题上边距（em）
    var h3Top: Double = 1.5
    /// 三级标题下边距（em）
    var h3Bottom: Double = 0.7
    /// 三级标题行高（比二级标题更紧）
    var h3LineHeight: Double = 1.45

    // MARK: - 列表

    /// 列表相对正文的额外缩进（em）
    var listIndent: Double = 1.2
    /// 列表项之间的间距（em）
    var listItemSpacing: Double = 0.35
    var listLineHeight: Double = 1.70
    var listMarkerWeight: Int = 500

    // MARK: - 图片

    /// 图片圆角（px）
    var imageRadius: Double = 8
    var imageShadow: Bool = true
    var imageSpacing: Double = 1.5

    // MARK: - 引用

    var quoteBarWidth: Double = 3
    var quoteRadius: Double = 8
    /// 引用底色 = 主题色按该比例混入白色
    var quoteBgTint: Double = 0.07
    var quoteTextColor: String = "#555555"

    // MARK: - 代码

    var codeBg: String = "#F7F8FA"
    var codeRadius: Double = 8
    /// 代码字号相对正文的缩放
    var codeScale: Double = 0.88

    // MARK: - 滚动块（<long-text> / <long-image> / <more-images>）

    /// 长文本块的最大高度（px），超出后内部上下滚动
    var longTextMaxHeight: Double = 320
    /// 长文本块底色
    var longTextBg: String = "#F7F9FC"
    /// 长文本块圆角
    var longTextRadius: Double = 8
    /// 长文本块内边距（em）
    var longTextPadding: Double = 0.9

    /// 长图的最大高度（px）。参考文章里用的是 450
    var longImageMaxHeight: Double = 450
    /// 长图圆角
    var longImageRadius: Double = 8

    /// 多图横滑时单张图的宽度（占容器百分比）
    var galleryImageWidth: Double = 72
    /// 多图横滑的图片间距（px）
    var galleryGap: Double = 12
    /// 多图横滑的圆角
    var galleryRadius: Double = 8

    /// 是否在滚动块下方显示「滑动查看」提示
    var scrollHintEnabled: Bool = true

    // MARK: - 外框卡片

    /// 整体内容外层米白圆角卡片（参考文章即为此结构）
    var cardEnabled: Bool = true
    var cardColor: String = "#F9F8F4"
    var cardRadius: Double = 24

    // MARK: - 预览

    /// 预览宽度：375 = 手机，677 = 公众号编辑区
    var previewWidth: Double = 375

    // MARK: - 常量

    static let defaultFontFamily =
        "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', 'Helvetica Neue', Arial, sans-serif"
    static let defaultMonoFamily =
        "SFMono-Regular, Menlo, Consolas, 'Liberation Mono', 'Courier New', monospace"

    // MARK: - 派生值

    /// 一级标题字号
    var h1FontSize: Double { Self.px(fontSize * h1Scale) }
    /// 二级标题字号
    var h2FontSize: Double { Self.px(fontSize * h2Scale) }
    /// 三级标题字号
    var h3FontSize: Double { Self.px(fontSize * h3Scale) }
    /// 四级标题字号（与正文同号，仅靠字重区分）
    var h4FontSize: Double { Self.px(fontSize * h4Scale) }
    /// 代码字号
    var codeFontSize: Double { Self.px(fontSize * codeScale) }
    /// 实际标题颜色
    var effectiveHeadingColor: String {
        switch headingColorMode {
        case .theme:  return themeColor
        case .dark:   return "#1D1D1F"
        case .custom: return customHeadingColor
        }
    }

    /// 实际加粗文本颜色
    var effectiveBoldColor: String {
        switch boldColorMode {
        case .theme:   return themeColor
        case .inherit: return textColor
        case .custom:  return customBoldColor
        }
    }

    /// 取整到 0.5px，避免出现 19.995px 这类脏值
    static func px(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    /// 输出 CSS 长度，整数不带小数点
    static func cssPx(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return "\(Int(r))px" }
        return "\(r)px"
    }

    /// 输出 em 数值
    static func cssEm(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        if r == r.rounded() { return "\(Int(r))em" }
        return "\(r)em"
    }

    /// 输出百分比
    static func cssPercent(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return "\(Int(r))%" }
        return "\(r)%"
    }
}

// MARK: - 持久化

enum ConfigStore {
    private static let key = "mpstyle.theme.v1"

    static func load() -> ThemeConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(ThemeConfig.self, from: data)
        else { return ThemeConfig() }
        return cfg
    }

    static func save(_ config: ThemeConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - 主题色预设

struct ThemePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let color: String

    static let all: [ThemePreset] = [
        .init(id: "blue",    name: "公众号蓝", color: "#1B63F3"),
        .init(id: "ink",     name: "墨黑",     color: "#1D1D1F"),
        .init(id: "wechat",  name: "微信绿",   color: "#07C160"),
        .init(id: "crimson", name: "朱砂红",   color: "#D93F3F"),
        .init(id: "violet",  name: "靛紫",     color: "#5856D6"),
        .init(id: "teal",    name: "湖蓝",     color: "#0E7C86"),
        .init(id: "amber",   name: "琥珀",     color: "#C2761B"),
    ]
}
