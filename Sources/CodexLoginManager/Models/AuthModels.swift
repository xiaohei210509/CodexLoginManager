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
            title: "正在检查",
            message: "正在读取本机 Codex 登录态并调用 Codex CLI 确认状态。",
            localAuthSummary: "待检查",
            cliStatus: "待检查",
            paths: paths,
            checkedAt: nil
        )
    }

    static func loginRunning(paths: CodexPaths) -> AuthStatus {
        AuthStatus(
            kind: .loginRunning,
            title: "登录流程运行中",
            message: "浏览器登录流程已启动，完成授权后这里会自动重新检查。",
            localAuthSummary: "等待 Codex 写入登录态",
            cliStatus: "codex login 正在运行",
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
