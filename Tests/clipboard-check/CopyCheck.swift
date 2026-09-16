import Foundation

// 把渲染结果写进系统剪贴板，用于验证「复制到公众号」这条路真的产出了 public.html。
// 之后用 `pbpaste -Prefer html` 读回来检查。

@main
struct CopyCheck {
    static func main() {
        let args = CommandLine.arguments
        let input = args.count > 1 ? args[1] : "Tests/sample.md"

        guard let markdown = try? String(contentsOfFile: input, encoding: .utf8) else {
            FileHandle.standardError.write("无法读取 \(input)\n".data(using: .utf8)!)
            exit(1)
        }

        let renderer = HTMLRenderer(config: ThemeConfig())
        let html = renderer.render(markdown)
        let plain = PlainTextRenderer.render(markdown)

        guard ClipboardExporter.copy(html: html, plainText: plain) else {
            FileHandle.standardError.write("写入剪贴板失败\n".data(using: .utf8)!)
            exit(1)
        }

        print("已写入剪贴板")
        print("HTML 片段  : \(html.count) 字符")
        print("纯文本回退 : \(plain.count) 字符")
        print("剪贴板含 HTML: \(ClipboardExporter.hasHTML)")
    }
}
