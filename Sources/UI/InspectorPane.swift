import SwiftUI

/// 右侧参数面板
struct InspectorPane: View {

    @EnvironmentObject private var state: AppState
    @State private var expanded: Set<String> = ["主题色", "正文", "加粗文本"]

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "排版参数") {
                Button("重置") { state.resetConfig() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 9) {
                    themeSection
                    bodySection
                    boldSection
                    headingSection
                    listSection
                    imageSection
                    scrollSection
                    quoteCodeSection
                    cardSection
                }
                .padding(10)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - 分组

    private var themeSection: some View {
        group("主题色") {
            VStack(alignment: .leading, spacing: 9) {
                ColorSwatches(selected: state.config.themeColor) { state.applyPreset($0) }
                HStack(spacing: 7) {
                    ColorPicker("", selection: themeColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 34)
                    HexField(hex: $state.config.themeColor)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var bodySection: some View {
        group("正文") {
            VStack(alignment: .leading, spacing: 8) {
                SettingSlider(title: "字号",
                              value: $state.config.fontSize,
                              range: 12...20, step: 0.5,
                              display: { "\(ThemeConfig.cssPx($0))" })
                SettingSlider(title: "字重",
                              value: bodyWeight,
                              range: 100...700, step: 100,
                              display: { "\(Int($0))" })
                SettingSlider(title: "行高",
                              value: $state.config.lineHeight,
                              range: 1.2...2.6, step: 0.05,
                              display: { String(format: "%.2f", $0) })
                SettingSlider(title: "字距",
                              value: $state.config.letterSpacing,
                              range: 0...0.3, step: 0.01,
                              display: { String(format: "%.2fem", $0) })
                SettingSlider(title: "段间距",
                              value: $state.config.paragraphSpacing,
                              range: 0.4...3, step: 0.1,
                              display: { String(format: "%.1fem", $0) })
                Toggle("两端对齐", isOn: $state.config.textAlignJustify)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    /// 加粗文本：字重与颜色都可调
    private var boldSection: some View {
        group("加粗文本") {
            VStack(alignment: .leading, spacing: 8) {
                SettingSlider(title: "字重",
                              value: boldWeight,
                              range: 400...900, step: 100,
                              display: { "\(Int($0))" })
                Picker("", selection: $state.config.boldColorMode) {
                    ForEach(BoldColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                if state.config.boldColorMode == .custom {
                    HStack(spacing: 7) {
                        ColorPicker("", selection: boldColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 34)
                        HexField(hex: $state.config.customBoldColor)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("实际颜色").font(.system(size: 11))
                        Spacer(minLength: 4)
                        Circle()
                            .fill(Color(hex: state.config.effectiveBoldColor))
                            .frame(width: 11, height: 11)
                        Text(state.config.effectiveBoldColor)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    /// 三种定制滚动块
    private var scrollSection: some View {
        group("滚动块") {
            VStack(alignment: .leading, spacing: 8) {
                Text("长文本 ↓  长图 ↕  多图 ↔")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Toggle("显示滑动提示", isOn: $state.config.scrollHintEnabled)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Divider().padding(.vertical, 1)

                SettingSlider(title: "长文本限高",
                              value: $state.config.longTextMaxHeight,
                              range: 160...640, step: 10,
                              display: { "\(Int($0))px" })
                SettingSlider(title: "长文本圆角",
                              value: $state.config.longTextRadius,
                              range: 0...24, step: 1,
                              display: { "\(Int($0))px" })
                HStack(spacing: 7) {
                    Text("长文本底色").font(.system(size: 11.5))
                    Spacer(minLength: 4)
                    HexField(hex: $state.config.longTextBg)
                }

                Divider().padding(.vertical, 1)

                SettingSlider(title: "长图限高",
                              value: $state.config.longImageMaxHeight,
                              range: 200...800, step: 10,
                              display: { "\(Int($0))px" })
                SettingSlider(title: "长图圆角",
                              value: $state.config.longImageRadius,
                              range: 0...24, step: 1,
                              display: { "\(Int($0))px" })

                Divider().padding(.vertical, 1)

                SettingSlider(title: "图集图片宽度",
                              value: $state.config.galleryImageWidth,
                              range: 40...100, step: 1,
                              display: { "\(Int($0))%" })
                SettingSlider(title: "图集间距",
                              value: $state.config.galleryGap,
                              range: 0...32, step: 1,
                              display: { "\(Int($0))px" })
                SettingSlider(title: "图集圆角",
                              value: $state.config.galleryRadius,
                              range: 0...24, step: 1,
                              display: { "\(Int($0))px" })
            }
        }
    }

    private var headingSection: some View {        group("标题") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $state.config.headingColorMode) {
                    ForEach(HeadingColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                if state.config.headingColorMode == .custom {
                    HStack(spacing: 7) {
                        ColorPicker("", selection: headingColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 34)
                        HexField(hex: $state.config.customHeadingColor)
                        Spacer(minLength: 0)
                    }
                }

                SettingSlider(title: "标题字重",
                              value: headingWeight,
                              range: 400...800, step: 100,
                              display: { "\(Int($0))" })
                SettingSlider(title: "二级字号",
                              value: $state.config.h2Scale,
                              range: 1.0...2.0, step: 0.01,
                              display: { _ in "\(ThemeConfig.cssPx(state.config.h2FontSize))" })
                SettingSlider(title: "二级行高",
                              value: $state.config.h2LineHeight,
                              range: 1.1...2.0, step: 0.05,
                              display: { String(format: "%.2f", $0) })
                SettingSlider(title: "三级字号",
                              value: $state.config.h3Scale,
                              range: 1.0...1.8, step: 0.01,
                              display: { _ in "\(ThemeConfig.cssPx(state.config.h3FontSize))" })
                SettingSlider(title: "三级行高",
                              value: $state.config.h3LineHeight,
                              range: 1.0...1.8, step: 0.05,
                              display: { String(format: "%.2f", $0) })
                SettingSlider(title: "二级上边距",
                              value: $state.config.h2Top,
                              range: 0.5...3, step: 0.1,
                              display: { String(format: "%.1fem", $0) })
                SettingSlider(title: "三级上边距",
                              value: $state.config.h3Top,
                              range: 0.5...3, step: 0.1,
                              display: { String(format: "%.1fem", $0) })
            }
        }
    }

    private var listSection: some View {
        group("列表") {
            VStack(alignment: .leading, spacing: 8) {
                SettingSlider(title: "缩进",
                              value: $state.config.listIndent,
                              range: 0...2.5, step: 0.1,
                              display: { String(format: "%.1fem", $0) })
                SettingSlider(title: "项间距",
                              value: $state.config.listItemSpacing,
                              range: 0...1.2, step: 0.05,
                              display: { String(format: "%.2fem", $0) })
                SettingSlider(title: "列表行高",
                              value: $state.config.listLineHeight,
                              range: 1.2...2.4, step: 0.05,
                              display: { String(format: "%.2f", $0) })
            }
        }
    }

    private var imageSection: some View {
        group("图片") {
            VStack(alignment: .leading, spacing: 8) {
                SettingSlider(title: "圆角",
                              value: $state.config.imageRadius,
                              range: 0...24, step: 1,
                              display: { "\(Int($0))px" })
                SettingSlider(title: "上下留白",
                              value: $state.config.imageSpacing,
                              range: 0.5...3, step: 0.1,
                              display: { String(format: "%.1fem", $0) })
                Toggle("阴影", isOn: $state.config.imageShadow)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    private var quoteCodeSection: some View {
        group("引用与代码") {
            VStack(alignment: .leading, spacing: 8) {
                SettingSlider(title: "引用底色",
                              value: $state.config.quoteBgTint,
                              range: 0...0.25, step: 0.01,
                              display: { _ in "\(Int(state.config.quoteBgTint * 100))%" })
                SettingSlider(title: "引用圆角",
                              value: $state.config.quoteRadius,
                              range: 0...16, step: 1,
                              display: { "\(Int($0))px" })
                SettingSlider(title: "代码字号比",
                              value: $state.config.codeScale,
                              range: 0.7...1.1, step: 0.01,
                              display: { _ in "\(ThemeConfig.cssPx(state.config.codeFontSize))" })
                SettingSlider(title: "代码圆角",
                              value: $state.config.codeRadius,
                              range: 0...16, step: 1,
                              display: { "\(Int($0))px" })
                HStack(spacing: 7) {
                    Text("代码块底色").font(.system(size: 11.5))
                    Spacer(minLength: 4)
                    HexField(hex: $state.config.codeBg)
                }
            }
        }
    }

    private var cardSection: some View {
        group("外框卡片") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("启用内容卡片", isOn: $state.config.cardEnabled)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                if state.config.cardEnabled {
                    HStack(spacing: 7) {
                        ColorPicker("", selection: cardColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 34)
                        HexField(hex: $state.config.cardColor)
                        Spacer(minLength: 0)
                    }
                    SettingSlider(title: "卡片圆角",
                                  value: $state.config.cardRadius,
                                  range: 0...40, step: 1,
                                  display: { "\(Int($0))px" })
                }
            }
        }
    }

    // MARK: - 折叠容器

    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        let isOpen = Binding(
            get: { expanded.contains(title) },
            set: { open in
                if open { expanded.insert(title) } else { expanded.remove(title) }
            }
        )
        return DisclosureGroup(isExpanded: isOpen) {
            content().padding(.top, 7)
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - 绑定桥接

    private var themeColorBinding: Binding<Color> {
        Binding(get: { Color(hex: state.config.themeColor) },
                set: { state.config.themeColor = $0.hexString })
    }

    private var headingColorBinding: Binding<Color> {
        Binding(get: { Color(hex: state.config.customHeadingColor) },
                set: { state.config.customHeadingColor = $0.hexString })
    }

    private var cardColorBinding: Binding<Color> {
        Binding(get: { Color(hex: state.config.cardColor) },
                set: { state.config.cardColor = $0.hexString })
    }

    private var bodyWeight: Binding<Double> {
        Binding(get: { Double(state.config.bodyWeight) },
                set: { state.config.bodyWeight = Int($0) })
    }

    private var boldWeight: Binding<Double> {
        Binding(get: { Double(state.config.boldWeight) },
                set: { state.config.boldWeight = Int($0) })
    }

    private var boldColorBinding: Binding<Color> {
        Binding(get: { Color(hex: state.config.customBoldColor) },
                set: { state.config.customBoldColor = $0.hexString })
    }

    private var headingWeight: Binding<Double> {
        Binding(get: { Double(state.config.headingWeight) },
                set: { state.config.headingWeight = Int($0) })
    }
}
