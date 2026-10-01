import SwiftUI
import Combine
import UniformTypeIdentifiers

/// 应用状态：Markdown 原文、排版参数、渲染产物。
/// 全程只在主线程使用（Combine 的 sink 调度在 RunLoop.main）。
final class AppState: ObservableObject {

    @Published var markdown: String = SampleDocument.text
    @Published var config: ThemeConfig = ConfigStore.load()

    /// 可复制到公众号的 HTML 片段
    @Published private(set) var html: String = ""
    /// 预览页骨架（只与主题色 / 宽度 / 字体有关）
    @Published private(set) var shell: String = ""

    /// 轻提示文案
    @Published var toast: String?

    // MARK: - 发布到公众号草稿箱

    /// 发布配置（AppID、标题、封面等）
    @Published var publishConfig: PublishConfig = PublishConfigStore.load()
    /// AppSecret。界面里可编辑，落盘时进钥匙串而不是 UserDefaults。
    @Published var appSecret: String = Keychain.get(.wechatAppSecret) ?? ""
    /// 发布进度流水
    @Published var publishProgress = PublishProgress()
    /// 是否展开发布面板
    @Published var showPublishSheet = false

    private var bag = Set<AnyCancellable>()
    private var toastWork: DispatchWorkItem?

    init() {
        rebuild()

        // 正文或参数变化 → 重新渲染（轻微防抖，避免连续输入时反复全量解析）
        Publishers.CombineLatest($markdown, $config)
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)

        // 参数变化 → 持久化
        $config
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { ConfigStore.save($0) }
            .store(in: &bag)

        // 发布配置变化 → 持久化
        $publishConfig
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { PublishConfigStore.save($0) }
            .store(in: &bag)

        // AppSecret 变化 → 存钥匙串（不放 UserDefaults）
        $appSecret
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { secret in
                if secret.isEmpty {
                    Keychain.delete(.wechatAppSecret)
                } else {
                    Keychain.set(secret, for: .wechatAppSecret)
                }
            }
            .store(in: &bag)
    }

    /// 钥匙串里是否已经存过 AppSecret
    var hasStoredSecret: Bool {
        Keychain.get(.wechatAppSecret)?.isEmpty == false
    }

    private func rebuild() {
        let renderer = HTMLRenderer(config: config)
        shell = renderer.previewShell()
        html = renderer.render(markdown)
    }

    // MARK: - 动作

    /// 复制为公众号可粘贴的富文本
    func copyForWeChat() {
        let plain = PlainTextRenderer.render(markdown)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            flash("还没有内容可以复制")
            return
        }
        if ClipboardExporter.copy(html: html, plainText: plain) {
            flash("已复制，去公众号编辑器 ⌘V 粘贴")
        } else {
            flash("复制失败，请重试")
        }
    }

    func loadSample() {
        markdown = SampleDocument.text
        flash("已载入示例文档")
    }

    func clearAll() {
        markdown = ""
        flash("已清空")
    }

    func resetConfig() {
        config = ThemeConfig()
        flash("排版参数已重置")
    }

    func applyPreset(_ preset: ThemePreset) {
        config.themeColor = preset.color
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 Markdown 文件"
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.insert(md, at: 0) }
        if let markdownType = UTType(filenameExtension: "markdown") { types.insert(markdownType, at: 0) }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            markdown = text
            flash("已打开 \(url.lastPathComponent)")
        } catch {
            flash("读取失败：\(error.localizedDescription)")
        }
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "article.html"
        panel.message = "导出为 HTML 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            flash("已导出到 \(url.lastPathComponent)")
        } catch {
            flash("导出失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 轻提示

    /// 非 private：发布流程在 AppState+Publish.swift 里也要用
    func flash(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
