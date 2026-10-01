import SwiftUI
import UniformTypeIdentifiers

/// 发布到公众号草稿箱的完整流程。
///
/// 拆成独立文件是因为它跟编辑器/参数的耦合很弱：输入是「渲染好的 HTML + 一份配置」，
/// 输出是「一篇草稿」。中间只通过 publishProgress 汇报进度。
extension AppState {

    // MARK: - 入口

    func showPublishPanel() {
        publishProgress.reset()
        showPublishSheet = true
    }

    /// 测试 AppID / AppSecret 是否能拿到 access_token。
    /// IP 白名单没配的话这一步就会失败，比等到发布时才报错好得多。
    func testWeChatConnection() {
        guard !publishConfig.appID.isEmpty, !appSecret.isEmpty else {
            publishProgress.reset()
            publishProgress.log("先填 AppID 和 AppSecret", level: .warning)
            return
        }
        publishProgress.reset()
        publishProgress.isRunning = true

        let client = WeChatClient(appID: publishConfig.appID, secret: appSecret)
        Task { @MainActor in
            do {
                publishProgress.log("正在向微信请求 access_token…")
                _ = try await client.accessToken()
                publishProgress.log("鉴权通过，AppID 与 AppSecret 可用", level: .success)
            } catch {
                logError(error)
            }
            publishProgress.isRunning = false
        }
    }

    /// 选择封面图。draft/add 接口要求必须有封面，所以这是必填项。
    func chooseCoverImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择封面图（建议 900×383，jpg 或 png）"
        panel.allowedContentTypes = [.jpeg, .png, .image]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        publishConfig.coverPath = url.path
    }

    // MARK: - 主流程

    func publishDraft() {
        publishProgress.reset()

        let appID = publishConfig.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else {
            publishProgress.log("AppID 不能为空", level: .failure)
            return
        }
        guard !appSecret.isEmpty else {
            publishProgress.log("AppSecret 不能为空", level: .failure)
            return
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            publishProgress.log("正文是空的，没什么可发", level: .failure)
            return
        }
        guard !publishConfig.coverPath.isEmpty,
              FileManager.default.fileExists(atPath: publishConfig.coverPath) else {
            publishProgress.log("请先选一张封面图，微信要求草稿必须有封面", level: .failure)
            return
        }

        let title = resolvedTitle()
        let coverPath = publishConfig.coverPath
        let localize = publishConfig.localizeImages
        let shouldOpen = publishConfig.openDraftBoxAfterPublish
        let digest = publishConfig.digest.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = publishConfig.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = publishConfig.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = html

        publishProgress.isRunning = true
        publishProgress.log("开始发布：\(title)")

        Task { @MainActor in
            let client = WeChatClient(appID: appID, secret: appSecret)
            do {
                publishProgress.log("① 获取 access_token…")
                _ = try await client.accessToken()
                publishProgress.log("   鉴权通过", level: .success)

                var body = content
                if localize {
                    body = try await localizeImages(in: body, client: client)
                } else {
                    publishProgress.log("② 跳过图片本地化（外链图片发布后可能不显示）", level: .warning)
                }

                publishProgress.log("③ 上传封面图…")
                let coverData = try Data(contentsOf: URL(fileURLWithPath: coverPath))
                let coverName = (coverPath as NSString).lastPathComponent
                let thumbMediaID = try await client.uploadCoverImage(data: coverData, filename: coverName)
                publishProgress.log("   封面 media_id: \(thumbMediaID.prefix(24))…", level: .success)

                publishProgress.log("④ 写入草稿箱…")
                let article = DraftArticle(title: title,
                                           author: author,
                                           digest: digest,
                                           content: body,
                                           sourceURL: sourceURL,
                                           thumbMediaID: thumbMediaID)
                let draftID = try await client.addDraft(article)

                publishProgress.draftMediaID = draftID
                publishProgress.log("草稿已创建，media_id: \(draftID)", level: .success)
                publishProgress.log("去「公众号后台 → 内容与互动 → 草稿箱」即可看到，"
                                    + "在后台确认排版后再群发。", level: .success)
                flash("已发布到草稿箱")

                if shouldOpen, let url = URL(string: "https://mp.weixin.qq.com/") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                logError(error)
            }
            publishProgress.isRunning = false
        }
    }

    // MARK: - 图片本地化

    /// 把正文里的外链图片下载后上传到公众号，替换成 mmbiz 地址。
    ///
    /// 公众号对外站图片有防盗链，直接引用外链的草稿在发布后会显示成裂图，
    /// 所以这一步不做的话草稿基本是废的。
    private func localizeImages(in content: String, client: WeChatClient) async throws -> String {
        let sources = Self.imageSources(in: content)
        guard !sources.isEmpty else {
            publishProgress.log("② 正文里没有图片，跳过本地化", level: .success)
            return content
        }

        publishProgress.log("② 本地化 \(sources.count) 张正文图片…")

        var mapping: [String: String] = [:]
        for (index, src) in sources.enumerated() {
            // 已经是公众号自己的图床就直接跳过
            if src.contains("mmbiz.qpic.cn") || src.contains("mmbiz.qlogo.cn") {
                publishProgress.log("   [\(index + 1)/\(sources.count)] 已在公众号图床，跳过")
                continue
            }
            do {
                let url = try imageURL(from: src)
                let (data, _) = try await URLSession.shared.data(from: url)
                guard data.count < 1024 * 1024 else {
                    publishProgress.log("   [\(index + 1)/\(sources.count)] 超过 1MB，微信拒绝，跳过",
                                        level: .warning)
                    continue
                }
                let filename = url.lastPathComponent.isEmpty ? "image.jpg" : url.lastPathComponent
                let uploaded = try await client.uploadContentImage(data: data, filename: filename)
                mapping[src] = uploaded
                publishProgress.log("   [\(index + 1)/\(sources.count)] 已上传", level: .success)
            } catch {
                // 单张失败不中断整体流程，保留原外链并在日志里说明
                publishProgress.log("   [\(index + 1)/\(sources.count)] 失败：\(shortMessage(error))",
                                    level: .warning)
            }
        }

        guard !mapping.isEmpty else {
            publishProgress.log("   没有图片上传成功，正文保持原样", level: .warning)
            return content
        }
        return Self.replacingImageSources(in: content, mapping: mapping)
    }

    private func imageURL(from src: String) throws -> URL {
        if src.hasPrefix("//") {
            return URL(string: "https:\(src)")!
        }
        guard let url = URL(string: src) else {
            throw WeChatAPIError(code: -1, message: "图片地址不合法：\(src.prefix(60))")
        }
        return url
    }

    // MARK: - 纯函数

    /// 抽出 `<img>` 的 src，去重并保持顺序
    static func imageSources(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<img\\b[^>]*?\\bsrc=\"([^\"]+)\"",
                                                   options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let src = ns.substring(with: match.range(at: 1))
            guard !src.hasPrefix("data:"), seen.insert(src).inserted else { continue }
            result.append(src)
        }
        return result
    }

    /// 把 img 的 src 按映射替换掉
    static func replacingImageSources(in html: String, mapping: [String: String]) -> String {
        var result = html
        // 长的先替换，避免一个地址是另一个的前缀时被截断
        for (old, new) in mapping.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: "src=\"\(old)\"", with: "src=\"\(new)\"")
        }
        return result
    }

    /// 标题优先级：手动填的 > 正文第一个标题 > 正文第一行
    func resolvedTitle() -> String {
        let manual = publishConfig.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return manual }

        for node in BlockParser.parse(markdown) {
            if case .heading(_, let text) = node {
                let plain = Inline.flatten(InlineParser.parse(text))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !plain.isEmpty { return String(plain.prefix(64)) }
            }
        }
        let firstLine = markdown
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "未命名文章"
        return String(Inline.flatten(InlineParser.parse(firstLine)).prefix(64))
    }

    // MARK: - 辅助

    private func logError(_ error: Error) {
        if let api = error as? WeChatAPIError {
            publishProgress.log(api.fullText, level: .failure)
        } else {
            publishProgress.log(shortMessage(error), level: .failure)
        }
    }

    private func shortMessage(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }
}
