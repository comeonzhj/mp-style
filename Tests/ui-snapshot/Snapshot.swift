import SwiftUI
import AppKit

// 离屏渲染界面快照，用于开发期校验布局（不参与 App 打包）。
//
// ImageRenderer 渲染不了 ScrollView / TextEditor / WKWebView 这些 AppKit 支撑的控件，
// 所以这里用真实的 NSWindow + cacheDisplay 走完整布局流程。
//
// 用法: ui-snapshot <输出.png> [宽] [高] [root|inspector|editor] [等待秒数]

@main
struct UISnapshot {

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let args = CommandLine.arguments
        let outPath = args.count > 1 ? args[1] : "/tmp/mpstyle-ui.png"
        let width  = args.count > 2 ? (Double(args[2]) ?? 1360) : 1360
        let height = args.count > 3 ? (Double(args[3]) ?? 880) : 880
        let target = args.count > 4 ? args[4] : "root"
        let settle = args.count > 5 ? (Double(args[5]) ?? 2.0) : 2.0

        let state = AppState()

        let content: AnyView
        switch target {
        case "inspector":
            content = AnyView(InspectorPane().environmentObject(state))
        case "editor":
            content = AnyView(EditorPane().environmentObject(state))
        default:
            content = AnyView(RootView().environmentObject(state))
        }

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)

        hosting.layoutSubtreeIfNeeded()

        // 跑一段 RunLoop，让 WKWebView 有机会把预览页加载完
        let deadline = Date().addingTimeInterval(settle)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write("无法创建位图\n".data(using: .utf8)!)
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: outPath))
            print("已写出 \(outPath)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            FileHandle.standardError.write("写入失败: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }
}
