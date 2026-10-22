import Foundation
import XCTest
@testable import CodexLoginManager

final class CodexPathsTests: XCTestCase {
    func testAbbreviatesTheHomeDirectoryForDisplay() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertEqual(
            CodexPaths.abbreviatingHomeDirectory(in: homePath + "/.codex/auth.json"),
            "~/.codex/auth.json"
        )
    }

    func testPreservesPathsOutsideTheHomeDirectory() {
        XCTAssertEqual(
            CodexPaths.abbreviatingHomeDirectory(
                in: "/Applications/ChatGPT.app/Contents/Resources/codex"
            ),
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
    }

    func testDiscoversCurrentBundledCLIWithFinderPATH() throws {
        try withTemporaryHome { home in
            let app = home.appendingPathComponent("Applications/Codex.app")
            let cli = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
            try makeExecutable(cli)

            let paths = discover(home: home)

            XCTAssertEqual(paths.codexCLIPath, cli.path)
            XCTAssertEqual(paths.codexAppPath, app.path)
            XCTAssertEqual(paths.authPath, home.appendingPathComponent(".codex/auth.json").path)
        }
    }

    func testDiscoversNativeBundledFallback() throws {
        try withTemporaryHome { home in
            let app = home.appendingPathComponent("Applications/Codex.app")
            let cli = app.appendingPathComponent(
                "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
            )
            try makeExecutable(cli)

            XCTAssertEqual(discover(home: home).codexCLIPath, cli.path)
        }
    }

    func testKeepsLegacyBundledCLICompatible() throws {
        try withTemporaryHome { home in
            let cli = home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex")
            try makeExecutable(cli)

            XCTAssertEqual(discover(home: home).codexCLIPath, cli.path)
        }
    }

    func testBundledCLIHasPriorityOverPATH() throws {
        try withTemporaryHome { home in
            let bundled = home.appendingPathComponent(
                "Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"
            )
            let pathCLI = home.appendingPathComponent("bin/codex")
            try makeExecutable(bundled)
            try makeExecutable(pathCLI)

            XCTAssertEqual(
                discover(home: home, path: pathCLI.deletingLastPathComponent().path).codexCLIPath,
                bundled.path
            )
        }
    }

    func testDiscoversNVMWithoutShellInitializationAndSortsVersionsNumerically() throws {
        try withTemporaryHome { home in
            let newest = home.appendingPathComponent(".nvm/versions/node/v22.10.0/bin/codex")
            for version in ["v9.0.0", "v22.9.0", "v22.10.0"] {
                try makeExecutable(home.appendingPathComponent(".nvm/versions/node/\(version)/bin/codex"))
            }

            XCTAssertEqual(discover(home: home).codexCLIPath, newest.path)
        }
    }

    func testHonorsCustomNVMDirectory() throws {
        try withTemporaryHome { home in
            let nvm = home.appendingPathComponent("custom nvm")
            let cli = nvm.appendingPathComponent("versions/node/v24.1.0/bin/codex")
            try makeExecutable(cli)
            let paths = CodexPaths.discover(
                homeDirectory: home,
                environment: ["PATH": "/usr/bin:/bin", "NVM_DIR": nvm.path],
                appCandidates: [], fallbackDirectories: []
            )

            XCTAssertEqual(paths.codexCLIPath, cli.path)
        }
    }

    func testSearchesCommonInstallLocationsWithoutFinderPATH() throws {
        try withTemporaryHome { home in
            let bin = home.appendingPathComponent("homebrew/bin")
            try makeExecutable(bin.appendingPathComponent("codex"))
            let paths = CodexPaths.discover(
                homeDirectory: home, environment: ["PATH": "/usr/bin:/bin"],
                appCandidates: [], fallbackDirectories: [bin.path]
            )

            XCTAssertEqual(paths.codexCLIPath, bin.appendingPathComponent("codex").path)
        }
    }

    func testIgnoresNonExecutableAndBrokenSymlinkCandidates() throws {
        try withTemporaryHome { home in
            let bundled = home.appendingPathComponent(
                "Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"
            )
            try makeExecutable(bundled)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bundled.path)
            let broken = home.appendingPathComponent("bin/codex")
            try FileManager.default.createDirectory(
                at: broken.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "/nonexistent-codex")
            let fallback = home.appendingPathComponent(".local/bin/codex")
            try makeExecutable(fallback)

            XCTAssertEqual(
                discover(home: home, path: broken.deletingLastPathComponent().path).codexCLIPath,
                fallback.path
            )
        }
    }

    func testRediscoversCLIAfterAnInstallationLayoutChanges() throws {
        try withTemporaryHome { home in
            let old = home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex")
            let new = home.appendingPathComponent(
                "Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"
            )
            try makeExecutable(old)
            XCTAssertEqual(discover(home: home).codexCLIPath, old.path)
            try FileManager.default.removeItem(at: old)
            try makeExecutable(new)

            XCTAssertEqual(discover(home: home).codexCLIPath, new.path)
        }
    }

    private func discover(home: URL, path: String = "/usr/bin:/bin") -> CodexPaths {
        CodexPaths.discover(
            homeDirectory: home, environment: ["PATH": path],
            appCandidates: [home.appendingPathComponent("Applications/Codex.app").path],
            fallbackDirectories: []
        )
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }
}
