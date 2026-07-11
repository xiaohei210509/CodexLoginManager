import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CodexLoginManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: AuthViewModel

    init() {
        _viewModel = StateObject(wrappedValue: AuthViewModel(service: CodexAuthService()))
    }

    var body: some Scene {
        WindowGroup("Codex 登录管理") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 660, minHeight: 500)
                .task {
                    await viewModel.refresh()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("重新检查登录态") {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("启动浏览器登录") {
                    Task { await viewModel.startLogin() }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!viewModel.canStartLogin)
            }
        }
    }
}
