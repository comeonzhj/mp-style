import AppKit
import Foundation

// 用真实公众号账号跑一遍「渲染 → 上传图片 → 建草稿」的完整链路。
//
// 复用 App 里的 WeChatClient，所以测的就是产品实际走的那条代码路径。
//
// 用法: publish-check <.env 路径> [草稿标题]

@main
struct PublishCheck {

    static func main() async {
        let args = CommandLine.arguments
        let envPath = args.count > 1 ? args[1] : ".env"
        let title = args.count > 2 ? args[2] : "【测试】排版工具草稿箱连通性验证"

        // ── 读凭据 ──
        guard let env = readEnv(envPath) else {
            fail("读不到 \(envPath)")
        }
        guard let appID = env["AppID"], let secret = env["AppSecret"],
              !appID.isEmpty, !secret.isEmpty else {
            fail("\(envPath) 里缺 AppID 或 AppSecret")
        }

        print("—— 凭据 ——")
        print("  AppID      : \(appID.prefix(6))…\(appID.suffix(4))（\(appID.count) 位）")
        print("  AppSecret  : \(String(repeating: "*", count: secret.count))（\(secret.count) 位）")
        print()

        let client = WeChatClient(appID: appID, secret: secret)

        do {
            // ── 1. access_token ──
            step("① 获取 access_token")
            _ = try await client.accessToken()
            ok("鉴权通过")

            // ── 2. 本地化正文图片 ──
            step("② 上传正文图片")
            let markdown = sampleMarkdown()
            let config = ThemeConfig()
            var content = HTMLRenderer(config: config).render(markdown)

            let sources = AppState.imageSources(in: content)
            print("     正文里发现 \(sources.count) 张图片")
            var mapping: [String: String] = [:]
            for (index, src) in sources.enumerated() {
                do {
                    guard let url = URL(string: src.hasPrefix("//") ? "https:\(src)" : src) else { continue }
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let name = url.lastPathComponent.isEmpty ? "image.jpg" : url.lastPathComponent
                    print("     [\(index + 1)/\(sources.count)] 下载 \(data.count) 字节 → 上传…")
                    let uploaded = try await client.uploadContentImage(data: data, filename: name)
                    mapping[src] = uploaded
                    ok("     → \(uploaded.prefix(56))…")
                } catch {
                    warn("     [\(index + 1)] 失败: \(describe(error))")
                }
            }
            if !mapping.isEmpty {
                content = AppState.replacingImageSources(in: content, mapping: mapping)
                ok("已替换 \(mapping.count) 处图片地址")
            }

            // ── 3. 封面 ──
            step("③ 上传封面图")
            let cover = makeCoverPNG()
            print("     生成封面 \(cover.count) 字节")
            let thumbID = try await client.uploadCoverImage(data: cover, filename: "cover.png")
            ok("封面 media_id: \(thumbID)")

            // ── 4. 建草稿 ──
            step("④ 写入草稿箱")
            let article = DraftArticle(title: title,
                                       author: "MPStyle",
                                       digest: "这是排版工具自动提交的测试草稿，可以直接在后台删除。",
                                       content: content,
                                       sourceURL: "",
                                       thumbMediaID: thumbID)
            let draftID = try await client.addDraft(article)

            print()
            print("═══════════════════════════════════════")
            print("  草稿创建成功")
            print("  media_id : \(draftID)")
            print("  标题     : \(title)")
            print("  正文     : \(content.count) 字符")
            print("  去后台「内容与互动 → 草稿箱」查看")
            print("═══════════════════════════════════════")
            exit(0)

        } catch {
            print()
            fail(describe(error))
        }
    }

    // MARK: - 辅助

    /// 解析 .env。值可能被单引号、双引号或智能引号包裹，统一去壳。
    static func readEnv(_ path: String) -> [String: String]? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]

        let quotePairs: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}"),
        ]

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }

            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)

            // 去壳：值被引号包起来时把引号摘掉，否则 AppID 会多出两个字符直接导致鉴权失败
            for (open, close) in quotePairs where value.count >= 2 {
                if value.first == open, value.last == close {
                    value = String(value.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            result[key] = value
        }
        return result
    }

    static func sampleMarkdown() -> String {
        """
        # 排版工具草稿箱测试

        这是一篇由 **MPStyle** 自动提交的测试草稿，用来验证草稿箱链路是否打通。

        ## 检查项

        - 正文细体、行高、字距是否生效
        - `行内代码` 与 **加粗** 的颜色是否正确
        - 外链图片是否已被替换成公众号图床地址

        > 如果这段引用在后台显示正常，说明排版是完整的。

        ![测试图片](https://picsum.photos/seed/mpdraft/900/500)
        """
    }

    /// 现场生成一张 900×383 的封面，免得依赖外部文件
    static func makeCoverPNG() -> Data {
        let size = NSSize(width: 900, height: 383)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(calibratedRed: 0.106, green: 0.388, blue: 0.953, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let text = "MPStyle 草稿箱测试"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                              y: (size.height - textSize.height) / 2),
                  withAttributes: attributes)

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }

    static func describe(_ error: Error) -> String {
        (error as? WeChatAPIError)?.fullText ?? error.localizedDescription
    }

    static func step(_ text: String)  { print(text) }
    static func ok(_ text: String)    { print("  ✓ \(text)") }
    static func warn(_ text: String)  { print("  ! \(text)") }
    static func fail(_ text: String) -> Never {
        print("  ✗ \(text)")
        exit(1)
    }
}
