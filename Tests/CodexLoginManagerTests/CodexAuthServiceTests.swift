import Foundation
import XCTest
@testable import CodexLoginManager

final class CodexAuthServiceTests: XCTestCase {
    func testCheckStatusScrubsBothCLIStreamsWithoutEchoingMalformedAuth() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexLoginManagerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let accessKey = "access_" + "token"
        let refreshKey = "refresh_" + "token"
        let authSecret = "malformed-auth-secret-\(UUID().uuidString)"
        let stdoutSecret = "stdout-secret-\(UUID().uuidString)"
        let stderrSecret = "stderr-secret-\(UUID().uuidString)"
        let stdoutMarker = "Codex CLI vNext returned unfamiliar status text"
        let stderrMarker = "stderr diagnostic text remains visible"

        let authURL = root.appendingPathComponent("auth.json")
        let malformedAuth = "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"\(accessKey)\":\"\(authSecret)\"}"
        try Data(malformedAuth.utf8).write(to: authURL, options: .atomic)

        let cliURL = root.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        echo '{"\(accessKey)":"\(stdoutSecret)"}'
        echo '\(stdoutMarker)'
        echo '\(refreshKey)=\(stderrSecret)' >&2
        echo '\(stderrMarker)' >&2
        exit 23
        """
        try Data(script.utf8).write(to: cliURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)

        let paths = CodexPaths(
            codexCLIPath: cliURL.path,
            codexAppPath: root.appendingPathComponent("ChatGPT.app").path,
            authPath: authURL.path,
            configPath: root.appendingPathComponent("config.toml").path
        )
        let status = await CodexAuthService(paths: paths).checkStatus()

        XCTAssertEqual(status.kind, .invalidAuth)
        XCTAssertTrue(status.cliStatus.contains(stdoutMarker), status.cliStatus)
        XCTAssertTrue(status.cliStatus.contains(stderrMarker), status.cliStatus)

        let visibleText = [
            status.title,
            status.message,
            status.localAuthSummary,
            status.cliStatus
        ].joined(separator: "\n")
        XCTAssertFalse(visibleText.contains(authSecret), visibleText)
        XCTAssertFalse(visibleText.contains(stdoutSecret), visibleText)
        XCTAssertFalse(visibleText.contains(stderrSecret), visibleText)
    }

    func testLoginStatusRequiresAnExactSuccessfulPositiveLine() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexLoginManagerStatusTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let cliURL = root.appendingPathComponent("fake-codex")
        let paths = CodexPaths(
            codexCLIPath: cliURL.path,
            codexAppPath: root.appendingPathComponent("ChatGPT.app").path,
            authPath: root.appendingPathComponent("missing-auth.json").path,
            configPath: root.appendingPathComponent("config.toml").path
        )

        func writeCLI(output: String, exitCode: Int32) throws {
            let script = """
            #!/bin/sh
            echo '\(output)'
            exit \(exitCode)
            """
            try Data(script.utf8).write(to: cliURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
        }

        try writeCLI(output: "Not logged in using ChatGPT", exitCode: 0)
        let negativeStatus = await CodexAuthService(paths: paths).checkStatus()
        XCTAssertEqual(negativeStatus.kind, .missingAuth)

        try writeCLI(output: "  Logged in using ChatGPT  ", exitCode: 0)
        let positiveStatus = await CodexAuthService(paths: paths).checkStatus()
        XCTAssertEqual(positiveStatus.kind, .loggedIn)

        try writeCLI(output: "Logged in using ChatGPT", exitCode: 1)
        let failingStatus = await CodexAuthService(paths: paths).checkStatus()
        XCTAssertEqual(failingStatus.kind, .missingAuth)
    }

    func testUnknownAuthModeNeverEchoesItsRawValue() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexLoginManagerUnknownModeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let authModeSecret = "opaque-auth-mode-secret-$:%-\(UUID().uuidString)"
        let authURL = root.appendingPathComponent("auth.json")
        let authObject = ["auth_mode": authModeSecret]
        try JSONSerialization.data(withJSONObject: authObject)
            .write(to: authURL, options: .atomic)

        let cliURL = root.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        echo 'Not logged in using ChatGPT'
        exit 1
        """
        try Data(script.utf8).write(to: cliURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)

        let paths = CodexPaths(
            codexCLIPath: cliURL.path,
            codexAppPath: root.appendingPathComponent("ChatGPT.app").path,
            authPath: authURL.path,
            configPath: root.appendingPathComponent("config.toml").path
        )
        let status = await CodexAuthService(paths: paths).checkStatus()

        XCTAssertEqual(status.kind, .needsLogin)
        XCTAssertEqual(status.message, L10n.text("status.unknown.message"))
        XCTAssertEqual(status.localAuthSummary, L10n.text("auth.mode_unknown"))
        let visibleText = [
            status.title,
            status.message,
            status.localAuthSummary,
            status.cliStatus
        ].joined(separator: "\n")
        XCTAssertFalse(visibleText.contains(authModeSecret), visibleText)
    }
}
