import SwiftUI

/// 发布到公众号草稿箱的面板。
struct PublishSheet: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var revealSecret = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accountSection
                    articleSection
                    optionSection
                    progressSection
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 588, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: state.config.themeColor))
            VStack(alignment: .leading, spacing: 1) {
                Text("发布到公众号草稿箱")
                    .font(.system(size: 13, weight: .semibold))
                Text("发布后到公众号后台的草稿箱里预览、确认排版，再决定是否群发")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 账号

    private var accountSection: some View {
        card("账号") {
            VStack(alignment: .leading, spacing: 9) {
                labeled("AppID") {
                    TextField("wx 开头的字符串", text: $state.publishConfig.appID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                }
                labeled("AppSecret") {
                    HStack(spacing: 6) {
                        Group {
                            if revealSecret {
                                TextField("", text: $state.appSecret)
                            } else {
                                SecureField("", text: $state.appSecret)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))

                        Button {
                            revealSecret.toggle()
                        } label: {
                            Image(systemName: revealSecret ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help(revealSecret ? "隐藏" : "显示")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("AppSecret 存在系统钥匙串，不会写进配置文件")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("测试连接") { state.testWeChatConnection() }
                        .controlSize(.small)
                        .disabled(state.publishProgress.isRunning)
                }

                Text("在「公众号后台 → 设置与开发 → 基本配置」获取 AppID 与 AppSecret，"
                     + "并把本机公网 IP 加进同一页的 IP 白名单，否则接口会拒绝调用。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 文章

    private var articleSection: some View {
        card("文章") {
            VStack(alignment: .leading, spacing: 9) {
                labeled("标题") {
                    TextField(placeholderTitle, text: $state.publishConfig.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                }
                HStack(alignment: .top, spacing: 10) {
                    labeled("作者") {
                        TextField("可留空", text: $state.publishConfig.author)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                    }
                    labeled("摘要") {
                        TextField("留空由微信自动截取", text: $state.publishConfig.digest)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                    }
                }
                labeled("原文链接") {
                    TextField("可留空，填了会显示「阅读原文」", text: $state.publishConfig.sourceURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                }
                labeled("封面图") {
                    HStack(spacing: 7) {
                        Text(state.publishConfig.coverPath.isEmpty
                             ? "必填，建议 900×383"
                             : (state.publishConfig.coverPath as NSString).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundColor(state.publishConfig.coverPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("选择…") { state.chooseCoverImage() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var placeholderTitle: String {
        let resolved = state.resolvedTitle()
        return resolved.isEmpty ? "留空则取正文第一个标题" : "留空则用：\(resolved)"
    }

    // MARK: - 选项

    private var optionSection: some View {
        card("选项") {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("把正文里的外链图片上传到公众号", isOn: $state.publishConfig.localizeImages)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Text("公众号对外站图片有防盗链，不开这一项的话草稿发布后图片会变成裂图。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Toggle("发布成功后打开公众号后台", isOn: $state.publishConfig.openDraftBoxAfterPublish)
                    .font(.system(size: 11.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - 进度

    @ViewBuilder
    private var progressSection: some View {
        if !state.publishProgress.lines.isEmpty {
            card("进度") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.publishProgress.lines) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.level.symbol)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(color(for: line.level))
                                .frame(width: 10, alignment: .leading)
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(line.level == .failure ? color(for: .failure) : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                    if state.publishProgress.isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("进行中…").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func color(for level: PublishProgress.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .success: return Color(hex: "#1A9E5C")
        case .failure: return Color(hex: "#D93F3F")
        case .warning: return Color(hex: "#C77700")
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if let id = state.publishProgress.draftMediaID {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                    state.toast = "已复制 media_id"
                } label: {
                    Label("复制 media_id", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                state.publishDraft()
            } label: {
                if state.publishProgress.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("发布中…")
                    }
                } else {
                    Text("发布到草稿箱")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(state.publishProgress.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 组件

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func labeled<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
