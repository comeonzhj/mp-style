import Foundation

/// 把 `ThemeConfig` 翻译成一条条 CSS 声明字符串。
/// 所有输出都会被写进元素的 `style` 属性 —— 公众号编辑器会丢弃 `<style>` 标签和 class，
/// 只有内联样式能存活，所以这里产出的一切都必须是内联的。
struct StyleKit {

    let t: ThemeConfig

    init(t: ThemeConfig) {
        self.t = t
    }

    // MARK: - 基础色

    var theme: String    { HexColor.normalize(t.themeColor) }
    var body: String     { HexColor.normalize(t.textColor) }
    var heading: String  { HexColor.normalize(t.effectiveHeadingColor) }
    var muted: String    { HexColor.normalize(t.secondaryTextColor) }
    var quoteText: String { HexColor.normalize(t.quoteTextColor) }
    var codeBg: String   { HexColor.normalize(t.codeBg) }
    var cardBg: String   { HexColor.normalize(t.cardColor) }

    /// 主题色底纹：`share` 为主题色占比，越小越浅
    func themeTint(_ share: Double) -> String { HexColor.fade(theme, to: 1 - share) }

    /// 边框色：主题色淡化到接近中性灰
    var borderColor: String { HexColor.fade(theme, to: 0.88) }

    // MARK: - CSS 拼装

    /// 把声明列表拼成 `style` 属性的值。
    ///
    /// 关键约束：属性本身用双引号包裹，所以值里**绝不能出现双引号**，
    /// 否则属性会被浏览器提前截断，后面的声明全部失效。
    /// 这里统一把双引号降级成单引号（CSS 里两者等价）。
    private func css(_ pairs: [(String, String?)]) -> String {
        pairs.compactMap { key, value in value.map { "\(key): \($0)" } }
            .joined(separator: "; ")
            .replacingOccurrences(of: "\"", with: "'")
    }

    private func px(_ v: Double) -> String { ThemeConfig.cssPx(v) }
    private func em(_ v: Double) -> String { ThemeConfig.cssEm(v) }

    // MARK: - 正文

    /// 段落样式。`inQuote` 时收敛字号与间距，避免引用块内文字比正文还大。
    func paragraph(inQuote: Bool) -> String {
        if inQuote {
            return css([
                ("margin", "\(em(t.paragraphSpacing * 0.55)) 0"),
                ("font-size", px(ThemeConfig.px(t.fontSize * 0.96))),
                ("font-weight", "\(t.bodyWeight)"),
                ("line-height", "1.75"),
                ("letter-spacing", em(t.letterSpacing)),
                ("color", quoteText),
                ("text-align", t.textAlignJustify ? "justify" : "left"),
            ])
        }
        return css([
            ("margin", "\(em(t.paragraphSpacing)) 0"),
            ("font-size", px(t.fontSize)),
            ("font-weight", "\(t.bodyWeight)"),
            ("line-height", "\(t.lineHeight)"),
            ("letter-spacing", em(t.letterSpacing)),
            ("color", body),
            ("text-align", t.textAlignJustify ? "justify" : "left"),
        ])
    }

    // MARK: - 标题

    /// 标题样式。参考排版里的左侧渐变竖条已按要求移除，
    /// 标题颜色默认取主题色，并同正文左对齐（不再有左侧内缩）。
    func heading(level: Int) -> String {
        switch level {
        case 1:
            return css([
                ("margin", "\(em(t.h1Top)) 0 \(em(t.h1Bottom))"),
                ("padding", "0.2em 0 0.3em"),
                ("font-size", px(t.h1FontSize)),
                ("font-weight", "\(t.headingWeight)"),
                ("line-height", "1.5"),
                ("letter-spacing", "0.02em"),
                ("color", heading),
                ("text-align", "left"),
            ])
        case 2:
            return css([
                ("margin", "\(em(t.h2Top)) 0 \(em(t.h2Bottom))"),
                ("padding", "0.32em 0 0.4em"),
                ("font-size", px(t.h2FontSize)),
                ("font-weight", "\(t.headingWeight)"),
                ("line-height", "\(t.h2LineHeight)"),
                ("letter-spacing", "0.02em"),
                ("color", heading),
                ("text-align", "left"),
            ])
        case 3:
            // 与二级标题同构，但字号更小、行高更紧
            return css([
                ("margin", "\(em(t.h3Top)) 0 \(em(t.h3Bottom))"),
                ("padding", "0.22em 0 0.28em"),
                ("font-size", px(t.h3FontSize)),
                ("font-weight", "\(t.headingWeight)"),
                ("line-height", "\(t.h3LineHeight)"),
                ("letter-spacing", "0.02em"),
                ("color", heading),
                ("text-align", "left"),
            ])
        default:
            return css([
                ("margin", "1.3em 0 0.6em"),
                ("padding", "0.18em 0 0.22em"),
                ("font-size", px(t.h4FontSize)),
                ("font-weight", "\(t.headingWeight)"),
                ("line-height", "1.5"),
                ("letter-spacing", "0.02em"),
                ("color", heading),
                ("text-align", "left"),
            ])
        }
    }

    // MARK: - 列表

    /// 列表项：相对正文多一点点缩进，并采用悬挂缩进让折行对齐。
    /// 左外边距写进 margin 简写里，避免「先 margin 后 margin-left」被样式清洗器重排。
    func listItem(depth: Int) -> String {
        let indent = t.listIndent * Double(depth + 1)
        return css([
            ("margin", "\(em(t.listItemSpacing)) 0 \(em(t.listItemSpacing)) \(em(indent))"),
            ("text-indent", em(-t.listIndent)),
            ("font-size", px(t.fontSize)),
            ("font-weight", "\(t.bodyWeight)"),
            ("line-height", "\(t.listLineHeight)"),
            ("letter-spacing", em(t.letterSpacing)),
            ("color", body),
            ("text-align", "left"),
        ])
    }

    /// 序号 / 圆点：用主题色
    func listMarker() -> String {
        css([
            ("color", theme),
            ("font-weight", "\(t.listMarkerWeight)"),
        ])
    }

    // MARK: - 引用

    func blockquote(depth: Int) -> String {
        let pad = 1.05 + Double(depth) * 0.9
        // 嵌套时收紧外边距、加深一点底色，让内外层次分得开
        let margin = t.paragraphSpacing * (depth > 0 ? 0.6 : 1)
        let tint = t.quoteBgTint * (1 + Double(depth) * 0.8)
        return css([
            ("margin", "\(em(margin)) 0"),
            ("padding", "\(em(0.85)) \(em(pad))"),
            ("background-color", themeTint(tint)),
            ("border-left", "\(px(t.quoteBarWidth)) solid \(theme)"),
            ("border-radius", "0 \(px(t.quoteRadius)) \(px(t.quoteRadius)) 0"),
            ("box-sizing", "border-box"),
        ])
    }

    // MARK: - 代码

    func codeBlock() -> String {
        css([
            ("margin", "\(em(t.paragraphSpacing * 1.2)) 0"),
            ("padding", "1em 1.15em"),
            ("background-color", codeBg),
            ("border-radius", px(t.codeRadius)),
            ("font-size", px(t.codeFontSize)),
            ("line-height", "1.7"),
            ("letter-spacing", "0"),
            ("color", "#2B2B2B"),
            ("font-family", t.monoFamily),
            ("white-space", "pre-wrap"),
            ("word-break", "break-word"),
            ("overflow-x", "auto"),
            ("display", "block"),
        ])
    }

    func inlineCode() -> String {
        css([
            ("background-color", themeTint(0.10)),
            ("color", theme),
            ("padding", "0.12em 0.38em"),
            ("border-radius", "4px"),
            ("font-size", px(ThemeConfig.px(t.fontSize * 0.9))),
            ("font-family", t.monoFamily),
            ("letter-spacing", "0"),
        ])
    }

    // MARK: - 图片

    func image() -> String {
        css([
            ("max-width", "100%"),
            ("height", "auto"),
            ("display", "block"),
            ("margin", "\(em(t.imageSpacing)) auto"),
            ("border-radius", px(t.imageRadius)),
            ("box-shadow", t.imageShadow ? "0 8px 25px \(HexColor.rgba("#000000", alpha: 0.1))" : nil),
        ])
    }

    // MARK: - 行内元素

    /// 加粗：中等字重 + 主题色
    func strong() -> String {
        css([
            ("font-weight", "\(t.boldWeight)"),
            ("color", theme),
        ])
    }

    func emphasis() -> String {
        css([("font-style", "italic")])
    }

    func strikethrough() -> String {
        css([
            ("text-decoration", "line-through"),
            ("color", muted),
        ])
    }

    func link() -> String {
        css([
            ("color", theme),
            ("text-decoration", "none"),
            ("border-bottom", "1px solid \(HexColor.fade(theme, to: 0.45))"),
        ])
    }

    // MARK: - 分割线

    func divider() -> String {
        css([
            ("height", "1px"),
            ("background-color", HexColor.fade(theme, to: 0.86)),
            ("margin", "\(em(t.paragraphSpacing * 1.8)) 0"),
            ("font-size", "0"),
            ("line-height", "0"),
        ])
    }

    // MARK: - 表格

    func tableWrapper() -> String {
        css([
            ("margin", "\(em(t.paragraphSpacing)) 0"),
            ("overflow-x", "auto"),
        ])
    }

    func table() -> String {
        css([
            ("width", "100%"),
            ("border-collapse", "collapse"),
            ("border-spacing", "0"),
            ("font-size", px(ThemeConfig.px(t.fontSize * 0.93))),
            ("line-height", "1.6"),
        ])
    }

    func tableHeaderCell(align: ColumnAlign) -> String {
        css([
            ("border", "1px solid \(borderColor)"),
            ("background-color", themeTint(0.08)),
            ("padding", "0.5em 0.7em"),
            ("color", theme),
            ("font-weight", "\(t.boldWeight)"),
            ("font-size", px(ThemeConfig.px(t.fontSize * 0.93))),
            ("text-align", align.rawValue),
        ])
    }

    func tableCell(align: ColumnAlign) -> String {
        css([
            ("border", "1px solid \(borderColor)"),
            ("padding", "0.5em 0.7em"),
            ("color", body),
            ("font-weight", "\(t.bodyWeight)"),
            ("font-size", px(ThemeConfig.px(t.fontSize * 0.93))),
            ("text-align", align.rawValue),
        ])
    }

    // MARK: - 外框卡片

    /// 外框卡片。这里同时把字体栈显式写死：
    /// 不写的话，粘进公众号后会继承公众号自己的字体，与预览不一致。
    func card() -> String {
        css([
            ("background-color", cardBg),
            ("border-radius", px(t.cardRadius)),
            ("padding", "8px 12px"),
            ("box-sizing", "border-box"),
            ("font-family", t.fontFamily),
            ("font-size", px(t.fontSize)),
            ("color", body),
        ])
    }

    /// 无卡片时的外层容器，同样带上基础排版信息
    func plainWrapper() -> String {
        css([
            ("box-sizing", "border-box"),
            ("font-family", t.fontFamily),
            ("font-size", px(t.fontSize)),
            ("color", body),
        ])
    }
}
