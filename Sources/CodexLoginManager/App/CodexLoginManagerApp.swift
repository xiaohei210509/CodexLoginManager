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
        WindowGroup(L10n.text("app.window_title")) {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 660, minHeight: 500)
                .task {
                    await viewModel.refresh()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.text("menu.refresh")) {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(L10n.text("menu.login")) {
                    Task { await viewModel.startLogin() }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!viewModel.canStartLogin)
            }
        }
    }
}
