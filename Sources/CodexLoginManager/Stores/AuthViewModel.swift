import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var status: AuthStatus
    @Published private(set) var isBusy = false
    @Published private(set) var activityLog: String = ""

    private let service: CodexAuthService

    init(service: CodexAuthService) {
        self.service = service
        self.status = .checking(paths: service.paths)
    }

    var canStartLogin: Bool {
        status.canStartLogin && !isBusy
    }

    var canOpenCodexApp: Bool {
        status.paths.canOpenCodexApp && !isBusy
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        status = .checking(paths: service.paths)
        status = await service.checkStatus()
        activityLog = L10n.format("activity.check_complete", status.title)
        isBusy = false
    }

    func startLogin() async {
        guard canStartLogin else { return }
        isBusy = true
        status = .loginRunning(paths: service.paths)
        activityLog = L10n.text("activity.starting_login")

        let result = await service.startLogin()
        status = result.status
        activityLog = result.log
        isBusy = false
    }

    func openCodexApp() {
        service.openCodexApp()
    }
}
