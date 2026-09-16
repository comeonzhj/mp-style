import SwiftUI
import AppKit

// MARK: - 颜色互转

extension Color {
    init(hex: String) {
        let c = HexColor.components(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    var hexString: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return HexColor.hex(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

// MARK: - 面板容器

/// 分栏顶部的小标题条
struct PaneHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 参数分组卡片
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary)
            content()
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
}

// MARK: - 控件

/// 一行「标题 + 当前值 + 滑杆」
struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var hint: String = ""
    var display: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11.5))
                Spacer(minLength: 4)
                Text(hint.isEmpty ? display(value) : "\(display(value))  \(hint)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if step > 0 {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.mini)
            } else {
                Slider(value: $value, in: range)
                    .controlSize(.mini)
            }
        }
    }
}

/// 十六进制颜色输入框。
///
/// 内部用 draft + 焦点状态来区分「正在编辑」和「跟随外部变化」，
/// 这样既能在输入中间态保留用户敲的字符，又不用 `onChange`（macOS 14 起已弃用）。
struct HexField: View {
    @Binding var hex: String
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: Binding(
            get: { focused && !draft.isEmpty ? draft : hex },
            set: { draft = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11, design: .monospaced))
        .frame(width: 82)
        .focused($focused)
        .onSubmit(commit)
    }

    private func commit() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !text.hasPrefix("#") { text = "#" + text }

        let digits = text.dropFirst()
        let valid = (text.count == 7 || text.count == 4) && digits.allSatisfy({ $0.isHexDigit })
        if valid {
            hex = HexColor.normalize(text)
        }
        // 无论合法与否都丢弃草稿：非法输入回退显示原值
        draft = ""
        focused = false
    }
}

/// 主题色快捷色板
struct ColorSwatches: View {
    let selected: String
    let onPick: (ThemePreset) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ThemePreset.all) { preset in
                Button {
                    onPick(preset)
                } label: {
                    Circle()
                        .fill(Color(hex: preset.color))
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(isSelected(preset) ? 0.85 : 0.12),
                                        lineWidth: isSelected(preset) ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private func isSelected(_ preset: ThemePreset) -> Bool {
        HexColor.normalize(preset.color) == HexColor.normalize(selected)
    }
}

/// 轻提示
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color.black.opacity(0.82))
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
