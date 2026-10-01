import SwiftUI

/// 根视图：顶部操作条 + 三栏主体 + 轻提示
struct RootView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                HSplitView {
                    EditorPane()
                        .frame(minWidth: 300, idealWidth: 430)
                    PreviewPane()
                        .frame(minWidth: 360, idealWidth: 580)
                }
                Divider()
                InspectorPane()
                    .frame(width: 272)
            }
        }
        .frame(minWidth: 1020, minHeight: 660)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(text: toast)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toast)
        .sheet(isPresented: $state.showPublishSheet) {
            PublishSheet().environmentObject(state)
        }
    }

    // MARK: - 顶部操作条

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: state.config.themeColor))
                Text("公众号排版")
                    .font(.system(size: 13, weight: .semibold))
                Text("v\(BuildInfo.version)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.07))
                    )
            }

            Spacer(minLength: 8)

            Button {
                state.showPublishPanel()
            } label: {
                Label("发布到草稿箱", systemImage: "paperplane")
                    .font(.system(size: 12))
            }
            .controlSize(.regular)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .help("把当前文章写入公众号草稿箱（⇧⌘P）")

            Button {
                state.exportHTML()
            } label: {
                Label("导出 HTML", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12))
            }
            .controlSize(.regular)

            Button {
                state.copyForWeChat()
            } label: {
                Label("复制到公众号", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 4)
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: state.config.themeColor))
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("复制为公众号可粘贴格式（⇧⌘C）")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
