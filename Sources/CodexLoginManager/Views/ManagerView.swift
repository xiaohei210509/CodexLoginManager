import SwiftUI

struct ManagerView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var patch: DictationPatchViewModel
    @SceneStorage("manager.selectedTab") private var selectedTab = "login"

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(viewModel: auth, patchBusy: patch.isBusy, showsToolbar: selectedTab == "login")
                .tabItem { Label(L10n.text("tab.login"), systemImage: "key.fill") }
                .tag("login")

            DictationPatchView(viewModel: patch, loginBusy: auth.isBusy)
                .tabItem { Label(L10n.text("tab.dictation"), systemImage: "mic.badge.plus") }
                .tag("dictation")
        }
        .padding(.top, 8)
        .onChange(of: selectedTab) { _, value in
            if value == "dictation" { Task { await patch.refresh() } }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--show-dictation") {
                selectedTab = "dictation"
            }
        }
        .task { await patch.refresh() }
    }
}
