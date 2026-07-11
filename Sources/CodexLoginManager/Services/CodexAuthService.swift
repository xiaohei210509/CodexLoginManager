import AppKit
import Foundation

struct CodexAuthService: Sendable {
    let paths: CodexPaths
    private let runner: ProcessRunner

    init(
        paths: CodexPaths = .standard,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.paths = paths
        self.runner = runner
    }

    func checkStatus() async -> AuthStatus {
        guard FileManager.default.isExecutableFile(atPath: paths.codexCLIPath) else {
            return AuthStatus(
                kind: .missingCLI,
                title: "找不到 Codex CLI",
                message: "没有找到 ChatGPT/Codex app 内置的命令行工具，也没有在 PATH 中找到 codex。",
                localAuthSummary: readLocalAuthSummary().displayText,
                cliStatus: paths.codexCLIPath,
                paths: paths,
                checkedAt: Date()
            )
        }

        let localAuth = readLocalAuthSummary()
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

        return makeStatus(localAuth: localAuth, cliResult: cliResult)
    }

    func startLogin() async -> (status: AuthStatus, log: String) {
        guard FileManager.default.isExecutableFile(atPath: paths.codexCLIPath) else {
            return (
                status: AuthStatus(
                    kind: .missingCLI,
                    title: "找不到 Codex CLI",
                    message: "无法启动登录流程，请先确认 ChatGPT.app 安装在 /Applications，或 codex 在 PATH 中可执行。",
                    localAuthSummary: readLocalAuthSummary().displayText,
                    cliStatus: paths.codexCLIPath,
                    paths: paths,
                    checkedAt: Date()
                ),
                log: "Codex CLI 不存在：\(paths.codexCLIPath)"
            )
        }

        do {
            let result = try await runner.run(
                executablePath: paths.codexCLIPath,
                arguments: ["login"],
                timeoutSeconds: nil
            )

            let refreshed = await checkStatus()
            let output = Redactor.sanitize(result.combinedOutput)
            let prefix = result.exitCode == 0 ? "codex login 已结束。" : "codex login 退出码：\(result.exitCode)。"

            return (status: refreshed, log: "\(prefix)\n\(output)")
        } catch {
            let refreshed = await checkStatus()
            return (
                status: AuthStatus(
                    kind: .failed,
                    title: "登录启动失败",
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
        guard paths.canOpenCodexApp else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: paths.codexAppPath))
    }

    private func makeStatus(
        localAuth: LocalAuthSummary,
        cliResult: Result<ProcessResult, Error>
    ) -> AuthStatus {
        let cliText: String
        let cliConfirmed: Bool

        switch cliResult {
        case let .success(result):
            cliText = Redactor.sanitize(result.combinedOutput)
            cliConfirmed = result.combinedOutput.localizedCaseInsensitiveContains("Logged in using ChatGPT")
        case let .failure(error):
            cliText = Redactor.sanitize(error.localizedDescription)
            cliConfirmed = false
        }

        if cliConfirmed {
            return AuthStatus(
                kind: .loggedIn,
                title: "已登录：ChatGPT",
                message: "Codex CLI 已确认当前是 ChatGPT OAuth 登录态。",
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
                title: "需要登录",
                message: "没有找到 auth.json，点击一键登录会启动浏览器授权。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .apiKeyMode:
            return AuthStatus(
                kind: .apiKeyMode,
                title: "当前是 API key 模式",
                message: "未检测到 ChatGPT OAuth 登录态；可点击一键登录写入登录态，当前工具不会直接修改 config.toml。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .chatGPTTokenPresent:
            return AuthStatus(
                kind: .needsLogin,
                title: "登录态需要刷新",
                message: "auth.json 里有 ChatGPT token，但 Codex CLI 没有确认有效，建议重新登录。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .chatGPTMissingToken:
            return AuthStatus(
                kind: .needsLogin,
                title: "登录态不完整",
                message: "auth.json 标记为 ChatGPT 模式，但没有可用 access_token。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case let .otherMode(mode):
            return AuthStatus(
                kind: .needsLogin,
                title: "未知登录模式",
                message: "当前 auth_mode 是 \(mode)，不是 ChatGPT OAuth。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        case .invalid:
            return AuthStatus(
                kind: .invalidAuth,
                title: "auth.json 无法解析",
                message: "请检查 auth.json 是否是有效 JSON；也可以直接点击一键登录让 Codex 重新写入。",
                localAuthSummary: localAuth.displayText,
                cliStatus: cliText,
                paths: paths,
                checkedAt: Date()
            )
        }
    }

    private func readLocalAuthSummary() -> LocalAuthSummary {
        guard FileManager.default.fileExists(atPath: paths.authPath) else {
            return LocalAuthSummary(kind: .missing, displayText: "auth.json 不存在")
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: paths.authPath))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let root = object as? [String: Any] else {
                return LocalAuthSummary(kind: .invalid("root"), displayText: "auth.json 不是 JSON 对象")
            }

            let authMode = root["auth_mode"] as? String ?? ""
            let tokens = root["tokens"] as? [String: Any]
            let accessToken = tokens?["access_token"] as? String ?? ""

            if authMode == "chatgpt", !accessToken.isEmpty {
                return LocalAuthSummary(kind: .chatGPTTokenPresent, displayText: "auth_mode = chatgpt，access_token 存在")
            }

            if authMode == "chatgpt" {
                return LocalAuthSummary(kind: .chatGPTMissingToken, displayText: "auth_mode = chatgpt，但 access_token 为空")
            }

            if authMode == "apikey" {
                return LocalAuthSummary(kind: .apiKeyMode, displayText: "auth_mode = apikey")
            }

            if authMode.isEmpty {
                return LocalAuthSummary(kind: .otherMode("未设置"), displayText: "auth_mode 未设置")
            }

            return LocalAuthSummary(kind: .otherMode(authMode), displayText: "auth_mode = \(authMode)")
        } catch {
            return LocalAuthSummary(kind: .invalid(error.localizedDescription), displayText: "读取失败：\(error.localizedDescription)")
        }
    }
}
