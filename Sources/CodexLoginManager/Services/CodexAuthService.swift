import AppKit
import Foundation

struct CodexAuthService: Sendable {
    private let configuredPaths: CodexPaths?
    private let runner: ProcessRunner

    var paths: CodexPaths { configuredPaths ?? .standard }

    init(
        paths: CodexPaths? = nil,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.configuredPaths = paths
        self.runner = runner
    }

    func checkStatus() async -> AuthStatus {
        await checkStatus(paths: paths)
    }

    private func checkStatus(paths: CodexPaths) async -> AuthStatus {
        guard FileManager.default.isExecutableFile(atPath: paths.codexCLIPath) else {
            return AuthStatus(
                kind: .missingCLI,
                title: L10n.text("status.missing_cli.title"),
                message: L10n.text("status.missing_cli.message"),
                localAuthSummary: readLocalAuthSummary(paths: paths).displayText,
                cliStatus: paths.displayCLIPath,
                paths: paths,
                checkedAt: Date()
            )
        }

        let localAuth = readLocalAuthSummary(paths: paths)
        let cliResult: Result<ProcessResult, Error>

        do {
            let result = try await runner.run(
                executablePath: paths.codexCLIPath,
                arguments: ["login", "status"],
                timeoutSeconds: 20
            )
            cliResult = .success(result)
        } catch {
            cliResult = .failure(error)
        }

        return makeStatus(paths: paths, localAuth: localAuth, cliResult: cliResult)
    }

    func startLogin() async -> (status: AuthStatus, log: String) {
        let paths = self.paths
        guard FileManager.default.isExecutableFile(atPath: paths.codexCLIPath) else {
            return (
                status: AuthStatus(
                    kind: .missingCLI,
                    title: L10n.text("status.missing_cli.title"),
                    message: L10n.text("status.missing_cli.login_message"),
                    localAuthSummary: readLocalAuthSummary(paths: paths).displayText,
                    cliStatus: paths.displayCLIPath,
                    paths: paths,
                    checkedAt: Date()
                ),
                log: L10n.format("status.missing_cli.log", paths.displayCLIPath)
            )
        }

        do {
            let result = try await runner.run(
                executablePath: paths.codexCLIPath,
                arguments: ["login"],
                timeoutSeconds: nil
            )

            let refreshed = await checkStatus(paths: paths)
            let output = Redactor.sanitize(result.combinedOutput)
            let prefix = result.exitCode == 0
                ? L10n.text("status.login.finished")
                : L10n.format("status.login.exit", result.exitCode)

            return (status: refreshed, log: "\(prefix)\n\(output)")
        } catch {
            let refreshed = await checkStatus(paths: paths)
            return (
                status: AuthStatus(
                    kind: .failed,
                    title: L10n.text("status.login.failed_title"),
                    message: error.localizedDescription,
                    localAuthSummary: refreshed.localAuthSummary,
                    cliStatus: refreshed.cliStatus,
                    paths: paths,
                    checkedAt: Date()
                ),
                log: Redactor.sanitize(error.localizedDescription)
            )
        }
    }

    @MainActor
    func openCodexApp() {
        let paths = self.paths
        guard paths.canOpenCodexApp else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: paths.codexAppPath))
    }

    private func makeStatus(
        paths: CodexPaths,
        localAuth: LocalAuthSummary,
        cliResult: Result<ProcessResult, Error>
    ) -> AuthStatus {
        let cliText: String
        let cliConfirmed: Bool

        switch cliResult {
        case let .success(result):
            cliText = Redactor.sanitize(result.combinedOutput)
            cliConfirmed = result.exitCode == 0 && result.combinedOutput
                .components(separatedBy: .newlines)
                .contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare("Logged in using ChatGPT") == .orderedSame
                }
        case let .failure(error):
            cliText = Redactor.sanitize(error.localizedDescription)
            cliConfirmed = false
        }

        if cliConfirmed {
            return AuthStatus(
                kind: .loggedIn,
                title: L10n.text("status.logged_in.title"),
                message: L10n.text("status.logged_in.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        }

        switch localAuth.kind {
        case .missing:
            return AuthStatus(
                kind: .missingAuth,
                title: L10n.text("status.needs_login.title"),
                message: L10n.text("status.needs_login.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .apiKeyMode:
            return AuthStatus(
                kind: .apiKeyMode,
                title: L10n.text("status.api_key.title"),
                message: L10n.text("status.api_key.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .chatGPTTokenPresent:
            return AuthStatus(
                kind: .needsLogin,
                title: L10n.text("status.refresh.title"),
                message: L10n.text("status.refresh.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .chatGPTMissingToken:
            return AuthStatus(
                kind: .needsLogin,
                title: L10n.text("status.incomplete.title"),
                message: L10n.text("status.incomplete.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .otherMode:
            return AuthStatus(
                kind: .needsLogin,
                title: L10n.text("status.unknown.title"),
                message: L10n.text("status.unknown.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .invalid:
            return AuthStatus(
                kind: .invalidAuth,
                title: L10n.text("status.invalid.title"),
                message: L10n.text("status.invalid.message"),
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        }
    }

    private func readLocalAuthSummary(paths: CodexPaths) -> LocalAuthSummary {
        guard FileManager.default.fileExists(atPath: paths.authPath) else {
            return LocalAuthSummary(kind: .missing, displayText: L10n.text("auth.missing"))
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: paths.authPath))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let root = object as? [String: Any] else {
                return LocalAuthSummary(kind: .invalid("root"), displayText: L10n.text("auth.not_object"))
            }

            let authMode = root["auth_mode"] as? String ?? ""
            let tokens = root["tokens"] as? [String: Any]
            let accessToken = tokens?["access_token"] as? String ?? ""

            if authMode == "chatgpt", !accessToken.isEmpty {
                return LocalAuthSummary(kind: .chatGPTTokenPresent, displayText: L10n.text("auth.chatgpt_token"))
            }

            if authMode == "chatgpt" {
                return LocalAuthSummary(kind: .chatGPTMissingToken, displayText: L10n.text("auth.chatgpt_empty"))
            }

            if authMode == "apikey" {
                return LocalAuthSummary(kind: .apiKeyMode, displayText: L10n.text("auth.api_key"))
            }

            if authMode.isEmpty {
                return LocalAuthSummary(
                    kind: .otherMode,
                    displayText: L10n.text("auth.mode_missing")
                )
            }

            return LocalAuthSummary(
                kind: .otherMode,
                displayText: L10n.text("auth.mode_unknown")
            )
        } catch {
            return LocalAuthSummary(
                kind: .invalid(error.localizedDescription),
                displayText: L10n.format("auth.read_failed", error.localizedDescription)
            )
        }
    }
}
