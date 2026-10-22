import XCTest
@testable import CodexLoginManager

final class DictationPatchTests: XCTestCase {
    private func status(
        state: DictationPatchState = .off, running: Int = 0, recovery: Bool = false,
        backup: Bool = true, artifact: Bool = true, writable: Bool = true
    ) -> DictationPatchStatus {
        DictationPatchStatus(
            state: state, installedApp: "/Applications/ChatGPT.app",
            installedVersion: "26.1016.51333", supportedVersion: "26.1016.51333",
            runningProcessCount: running, recoveryRequired: recovery,
            officialBackupAvailable: backup, patchedArtifactAvailable: artifact,
            installationWritable: writable, checkedAt: "2026-10-22T02:00:00Z"
        )
    }

    func testOnlyStoppedSupportedReadyInstallationCanSwitch() {
        XCTAssertTrue(status().canSwitch)
        XCTAssertTrue(status(state: .on).canSwitch)
        XCTAssertFalse(status(running: 1).canSwitch)
        XCTAssertFalse(status(state: .unknown).canSwitch)
        XCTAssertFalse(status(state: .missing).canSwitch)
        XCTAssertFalse(status(recovery: true).canSwitch)
        XCTAssertFalse(status(backup: false).canSwitch)
        XCTAssertFalse(status(artifact: false).canSwitch)
        XCTAssertFalse(status(writable: false).canSwitch)
    }

    func testRecoveryStillAvailableWhenInstallationIsMissing() {
        XCTAssertTrue(status(state: .missing, recovery: true).canRecover)
        XCTAssertFalse(status(running: 1, recovery: true).canRecover)
        XCTAssertFalse(status(recovery: true, writable: false).canRecover)
        XCTAssertFalse(status().canRecover)
    }

    func testDecodesStructuredStatus() throws {
        let encoded = try JSONEncoder().encode(status(running: 3))
        let json = """
        {"schemaVersion":1,"ok":true,"status":\(String(decoding: encoded, as: UTF8.self)),"log":"","error":null}
        """
        let response = try DictationPatchResponse.decode(json)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.status?.state, .off)
        XCTAssertEqual(response.status?.runningProcessCount, 3)
        XCTAssertFalse(response.status?.canSwitch ?? true)
    }

    func testRejectsUnsupportedProtocolAndMalformedState() {
        XCTAssertThrowsError(try DictationPatchResponse.decode(
            #"{"schemaVersion":2,"ok":true,"status":null,"log":"","error":null}"#
        ))
        XCTAssertThrowsError(try DictationPatchResponse.decode("not JSON"))
        XCTAssertThrowsError(try JSONDecoder().decode(
            DictationPatchState.self, from: Data(#""unexpected""#.utf8)
        ))
    }

    func testFailedCommandPreservesFailureMessage() throws {
        let response = try DictationPatchResponse.decode(
            #"{"schemaVersion":1,"ok":false,"status":null,"log":"not modified","error":{"message":"Codex is running"}}"#
        )
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.message, "Codex is running")
    }

    func testPatchStringsExistInBothLanguages() {
        let keys = [
            "tab.dictation", "patch.title", "patch.confirm_on", "patch.confirm_restore",
            "patch.state.on", "patch.state.off", "patch.error.protocol", "patch.running_warning",
        ]
        for language in ["en-US", "zh-Hans-CN"] {
            for key in keys {
                XCTAssertNotEqual(L10n.text(key, preferredLanguages: [language]), key)
            }
        }
    }
}

final class DictationPatchServiceTests: XCTestCase, @unchecked Sendable {
    func testMissingToolFailsBeforeExecution() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await DictationPatchService(toolDirectory: directory, nodePath: "/bin/sh").execute(.status)
            XCTFail("A missing tool must fail")
        } catch let error as DictationPatchError {
            guard case .missingTool = error else { return XCTFail("Wrong error: \(error)") }
        } catch { XCTFail("\(error)") }
    }

    func testReadsJSONWithoutExecutingPatchCommands() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let script = directory.appendingPathComponent("dictation-patch.mjs")
        let contents = """
        test "$1" = "--json" && test "$2" = "status" || exit 3
        printf '%s\\n' '{"schemaVersion":1,"ok":true,"status":null,"log":"fixture","error":null}'
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        let response = try await DictationPatchService(
            toolDirectory: directory, nodePath: "/bin/sh"
        ).execute(.status)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.log, "fixture")
    }

    func testMissingRuntimeFailsClearly() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("dictation-patch.mjs"))
        do {
            _ = try await DictationPatchService(
                toolDirectory: directory, nodePath: "/nonexistent-node"
            ).execute(.status)
            XCTFail("A missing runtime must fail")
        } catch let error as DictationPatchError {
            guard case .missingNode = error else { return XCTFail("Wrong error: \(error)") }
        }
    }
}
