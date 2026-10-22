import Foundation

struct CodexPaths: Equatable, Sendable {
    let codexCLIPath: String
    let codexAppPath: String
    let authPath: String
    let configPath: String

    static var standard: CodexPaths {
        discover()
    }

    static func discover(
        homeDirectory home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appCandidates: [String]? = nil,
        fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> CodexPaths {
        let apps = appCandidates ?? [
            "/Applications/ChatGPT.app",
            "/Applications/Codex.app",
            home.appendingPathComponent("Applications/Codex.app").path,
            home.appendingPathComponent("Applications/ChatGPT.app").path,
        ]
        let install = resolvedCodexInstall(
            home: home, environment: environment, apps: apps,
            fallbackDirectories: fallbackDirectories
        )
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

    private static func resolvedCodexInstall(
        home: URL, environment: [String: String], apps: [String],
        fallbackDirectories: [String]
    ) -> (cliPath: String, appPath: String) {
        let fileManager = FileManager.default
        let bundledLocations = [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex",
        ]

        for appPath in apps {
            for location in bundledLocations {
                let cliPath = URL(fileURLWithPath: appPath)
                    .appendingPathComponent(location).path
                if fileManager.isExecutableFile(atPath: cliPath) {
                    return (cliPath: cliPath, appPath: appPath)
                }
            }
        }

        let appPath = apps.first { fileManager.fileExists(atPath: $0) }
            ?? apps.first ?? "/Applications/Codex.app"
        var directories = (environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        directories += fallbackDirectories
        directories += [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".nvm/current/bin").path,
        ]
        if let nvmBin = environment["NVM_BIN"] { directories.append(nvmBin) }
        let nvmRoot = environment["NVM_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".nvm")
        let versions = nvmRoot.appendingPathComponent("versions/node")
        if let entries = try? fileManager.contentsOfDirectory(
            at: versions, includingPropertiesForKeys: nil
        ) {
            directories += entries
                .filter { $0.lastPathComponent.hasPrefix("v") }
                .sorted {
                    $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric)
                        == .orderedDescending
                }
                .map {
                    versions.appendingPathComponent($0.lastPathComponent)
                        .appendingPathComponent("bin").path
                }
        }

        for directory in directories where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent("codex").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return (cliPath: candidate, appPath: appPath)
            }
        }

        return (
            cliPath: URL(fileURLWithPath: appPath)
                .appendingPathComponent(bundledLocations[0]).path,
            appPath: appPath
        )
    }
}

enum LocalAuthKind: Equatable, Sendable {
    case missing
    case chatGPTTokenPresent
    case chatGPTMissingToken
    case apiKeyMode
    case otherMode
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
