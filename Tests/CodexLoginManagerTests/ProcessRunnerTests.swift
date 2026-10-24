import Foundation
import XCTest
@testable import CodexLoginManager

final class ProcessRunnerTests: XCTestCase, @unchecked Sendable {
    func testDrainsLargeStdoutAndStderrBeforeWaitingForExit() async throws {
        let result = try await ProcessRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", "i=0; while [ \"$i\" -lt 12000 ]; do printf 'stdout line\\n'; printf 'stderr line\\n' >&2; i=$((i+1)); done"],
            timeoutSeconds: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, 144000)
        XCTAssertEqual(result.stderr.utf8.count, 144000)
    }

    func testEnvEntrypointCanFindItsSiblingRuntimeWithSpacesInPath() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("Codex runtime \(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }

        let cli = directory.appendingPathComponent("codex")
        let runtime = directory.appendingPathComponent("codex-manager-fixture-runtime")
        try Data("#!/usr/bin/env codex-manager-fixture-runtime\n".utf8).write(to: cli)
        try Data("#!/bin/sh\nprintf '%s\\n' 'fixture runtime found'\n".utf8).write(to: runtime)
        for file in [cli, runtime] {
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }

        let result = try await ProcessRunner().run(
            executablePath: cli.path, arguments: ["login", "status"], timeoutSeconds: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "fixture runtime found")
    }
}
