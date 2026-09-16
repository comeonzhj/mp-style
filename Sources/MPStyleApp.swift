import SwiftUI
import AppKit

@main
struct MPStyleApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("公众号排版工具") {
            RootView()
                .environmentObject(state)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            // 去掉「新建」，这个工具没有文档概念
            CommandGroup(replacing: .newItem) {}

            CommandMenu("排版") {
                Button("复制到公众号") { state.copyForWeChat() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("导出 HTML…") { state.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("打开 Markdown…") { state.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("载入示例文档") { state.loadSample() }
                Button("清空") { state.clearAll() }
                Divider()
                Button("重置排版参数") { state.resetConfig() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
