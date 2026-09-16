import SwiftUI

/// 左侧 Markdown 编辑区
struct EditorPane: View {

    @EnvironmentObject private var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "MARKDOWN", subtitle: stats) {
                HStack(spacing: 4) {
                    iconButton("doc.badge.plus", help: "打开 Markdown 文件") { state.openFile() }
                    iconButton("sparkles", help: "载入示例文档") { state.loadSample() }
                    iconButton("trash", help: "清空") { state.clearAll() }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.markdown)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .focused($focused)

                if state.markdown.isEmpty {
                    Text("在此粘贴 Markdown 原文…")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.secondary.opacity(0.65))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var stats: String {
        let chars = state.markdown.count
        let lines = state.markdown.isEmpty ? 0 : state.markdown.components(separatedBy: "\n").count
        return "\(chars) 字符 · \(lines) 行"
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
    }
}
