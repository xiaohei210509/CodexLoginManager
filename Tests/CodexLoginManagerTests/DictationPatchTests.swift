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

    func testFreshOfficialInstallationCanPrepareWithoutExternalArtifacts() {
        XCTAssertTrue(status().canSwitch)
        XCTAssertTrue(status(state: .on).canSwitch)
        XCTAssertFalse(status(running: 1).canSwitch)
        XCTAssertFalse(status(state: .unknown).canSwitch)
        XCTAssertFalse(status(state: .missing).canSwitch)
        XCTAssertFalse(status(state: .notNeeded).canSwitch)
        XCTAssertFalse(status(recovery: true).canSwitch)
        XCTAssertTrue(status(backup: false, artifact: false).canSwitch)
        XCTAssertTrue(status(state: .on, artifact: false).canSwitch)
        XCTAssertFalse(status(state: .on, backup: false).canSwitch)
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
    func testBundledRecipeIsAvailableWithoutNodeOrExternalDirectory() throws {
        let recipe = try DictationPatchRecipe.bundled()
        XCTAssertEqual(recipe.version, "26.1016.51333")
        XCTAssertNotEqual(recipe.originalArchiveSha256, recipe.patchedArchiveSha256)
        XCTAssertEqual(recipe.before.utf8.count, recipe.after.utf8.count)
        XCTAssertThrowsError(try recipe.patchArchive(Data()))
        XCTAssertThrowsError(try recipe.patchArchive(Data("unknown build".utf8)))
    }

    func testStatusDoesNotNeedOrCreateExternalResources() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        let service = DictationPatchService(installedApp: root.appendingPathComponent("missing.app"),
                                            storageDirectory: root.appendingPathComponent("storage"))
        let response = try await service.execute(.status)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.status?.state, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testUnknownInstallationIsNeverModified() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("unknown.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try manager.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let archive = resources.appendingPathComponent("app.asar")
        let original = Data("not a supported archive".utf8)
        try original.write(to: archive)
        let response = try await DictationPatchService(
            installedApp: app, storageDirectory: root.appendingPathComponent("storage")
        ).execute(.on)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.status?.state, .unknown)
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    func testLockExcludesConcurrentWritersAndReleasesWithoutStalePID() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: DictationPatchLock? = try DictationPatchLock(directory: directory)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try DictationPatchLock(directory: directory))
        first = nil
        let second = try DictationPatchLock(directory: directory)
        withExtendedLifetime(second) {}
    }

    func testLockRefusesSymbolicLinkWithoutTouchingItsTarget() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("untouched")
        let contents = Data("do not overwrite".utf8)
        try contents.write(to: target)
        try fm.createSymbolicLink(at: root.appendingPathComponent("operation.lock"), withDestinationURL: target)
        XCTAssertThrowsError(try DictationPatchLock(directory: root))
        XCTAssertEqual(try Data(contentsOf: target), contents)
    }

    func testRealOfficialFixtureRoundTripWhenExplicitlyProvided() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["CODEX_PATCH_OFFICIAL_FIXTURE"] else {
            throw XCTSkip("Set CODEX_PATCH_OFFICIAL_FIXTURE to a verified official app for the isolated integration test.")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CodexPatch-integration-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        let copied = try await ProcessRunner().run(executablePath: "/usr/bin/ditto", arguments: [fixture, app.path])
        XCTAssertEqual(copied.exitCode, 0, copied.combinedOutput)
        _ = try await ProcessRunner().run(executablePath: "/usr/bin/xattr", arguments: ["-cr", app.path])
        let service = DictationPatchService(installedApp: app, storageDirectory: root.appendingPathComponent("storage"))
        let initial = try await service.execute(.status)
        XCTAssertEqual(initial.status?.state, .off)
        XCTAssertTrue(initial.status?.canSwitch == true)
        let enabled = try await service.execute(.on)
        XCTAssertTrue(enabled.ok, enabled.error?.message ?? "")
        XCTAssertEqual(enabled.status?.state, .on)
        XCTAssertTrue(enabled.status?.officialBackupAvailable == true)
        XCTAssertTrue(enabled.status?.patchedArtifactAvailable == true)
        let disabled = try await service.execute(.off)
        XCTAssertTrue(disabled.ok, disabled.error?.message ?? "")
        XCTAssertEqual(disabled.status?.state, .off)
        let original = try DictationPatchRecipe.fileSHA(URL(fileURLWithPath: fixture)
            .appendingPathComponent("Contents/Resources/app.asar"))
        XCTAssertEqual(try DictationPatchRecipe.fileSHA(app.appendingPathComponent("Contents/Resources/app.asar")), original)
        let signature = try await ProcessRunner().run(executablePath: "/usr/bin/codesign", arguments: ["-dvv", app.path])
        XCTAssertTrue(signature.stderr.contains("TeamIdentifier=2DC432GLL2"))

        let builds = root.appendingPathComponent("storage/builds")
        let key = try XCTUnwrap(fm.contentsOfDirectory(atPath: builds.path).first)
        let planURL = builds.appendingPathComponent(key).appendingPathComponent("plan.json")
        var plan = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: planURL)) as? [String: Any])
        plan["patchedDigest"] = "damaged-cache"
        try JSONSerialization.data(withJSONObject: plan).write(to: planURL)
        let refused = try await service.execute(.on)
        XCTAssertFalse(refused.ok, "Corrupt cached digests must be rejected without a crash or app mutation")
        XCTAssertEqual(try DictationPatchRecipe.fileSHA(app.appendingPathComponent("Contents/Resources/app.asar")), original)
    }
}
