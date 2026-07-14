import Foundation

struct CodexPaths: Equatable, Sendable {
    let codexCLIPath: String
    let codexAppPath: String
    let authPath: String
    let configPath: String

    static var standard: CodexPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let install = resolvedCodexInstall()
        return CodexPaths(
            codexCLIPath: install.cliPath,
            codexAppPath: install.appPath,
            authPath: home.appendingPathComponent(".codex/auth.json").path,
            configPath: home.appendingPathComponent(".codex/config.toml").path
        )
    }

    var canOpenCodexApp: Bool {
        FileManager.default.fileExists(atPath: codexAppPath)
    }

    var displayAuthPath: String {
        Self.abbreviatingHomeDirectory(in: authPath)
    }

    var displayConfigPath: String {
        Self.abbreviatingHomeDirectory(in: configPath)
    }

    var displayCLIPath: String {
        Self.abbreviatingHomeDirectory(in: codexCLIPath)
    }

    static func abbreviatingHomeDirectory(in path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    private static func resolvedCodexInstall() -> (cliPath: String, appPath: String) {
        let fileManager = FileManager.default
        let appCandidates = [
            "/Applications/ChatGPT.app",
            "/Applications/Codex.app"
        ]

        for appPath in appCandidates {
            let cliPath = URL(fileURLWithPath: appPath)
                .appendingPathComponent("Contents/Resources/codex")
                .path

            if fileManager.isExecutableFile(atPath: cliPath) {
                return (cliPath: cliPath, appPath: appPath)
            }
        }

        if let cliPath = executablePath(named: "codex") {
            let appPath = appCandidates.first { fileManager.fileExists(atPath: $0) } ?? appCandidates[0]
            return (cliPath: cliPath, appPath: appPath)
        }

        return (
            cliPath: "/Applications/ChatGPT.app/Contents/Resources/codex",
            appPath: "/Applications/ChatGPT.app"
        )
    }

    private static func executablePath(named name: String) -> String? {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

        for directory in pathValue.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(name)
                .path

            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

enum LocalAuthKind: Equatable, Sendable {
    case missing
    case chatGPTTokenPresent
    case chatGPTMissingToken
    case apiKeyMode
    case otherMode(String)
    case invalid(String)
}

struct LocalAuthSummary: Equatable, Sendable {
    let kind: LocalAuthKind
    let displayText: String

    var hasChatGPTToken: Bool {
        kind == .chatGPTTokenPresent
    }
}

enum AuthStatusKind: String, Equatable, Sendable {
    case checking
    case loggedIn
    case needsLogin
    case apiKeyMode
    case missingAuth
    case missingCLI
    case invalidAuth
    case loginRunning
    case failed
}

struct AuthStatus: Equatable, Sendable {
    let kind: AuthStatusKind
    let title: String
    let message: String
    let localAuthSummary: String
    let cliStatus: String
    let paths: CodexPaths
    let checkedAt: Date?

    var isLoggedIn: Bool {
        kind == .loggedIn
    }

    var canStartLogin: Bool {
        kind != .checking && kind != .loginRunning && kind != .missingCLI
    }

    static func checking(paths: CodexPaths) -> AuthStatus {
        AuthStatus(
            kind: .checking,
            title: L10n.text("status.checking.title"),
            message: L10n.text("status.checking.message"),
            localAuthSummary: L10n.text("status.pending"),
            cliStatus: L10n.text("status.pending"),
            paths: paths,
            checkedAt: nil
        )
    }

    static func loginRunning(paths: CodexPaths) -> AuthStatus {
        AuthStatus(
            kind: .loginRunning,
            title: L10n.text("status.login_running.title"),
            message: L10n.text("status.login_running.message"),
            localAuthSummary: L10n.text("status.login_running.local"),
            cliStatus: L10n.text("status.login_running.cli"),
            paths: paths,
            checkedAt: nil
        )
    }
}

struct ProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
