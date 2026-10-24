import XCTest
@testable import CodexLoginManager

final class DictationPatchTransactionTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("off".utf8).write(to: root.appendingPathComponent("installed.app"))
        try Data("on".utf8).write(to: root.appendingPathComponent("source.app"))
        return root
    }

    private func validate(_ app: URL, _ state: DictationPatchState) async throws {
        try require(Data(contentsOf: app) == Data(state.rawValue.utf8))
    }

    private func copy(_ source: URL, _ target: URL) async throws {
        try FileManager.default.copyItem(at: source, to: target)
    }

    func testCommitReplacesOnlyTargetAndCleansJournal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await DictationPatchTransaction.replace(
            app: root.appendingPathComponent("installed.app"), source: root.appendingPathComponent("source.app"),
            journal: root.appendingPathComponent("journal.json"), mode: .on, previousMode: .off,
            validate: validate, stopped: {}, copy: copy
        )
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("installed.app")), Data("on".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testFailureAfterMovingOriginalRollsBack() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try await DictationPatchTransaction.replace(
                app: root.appendingPathComponent("installed.app"), source: root.appendingPathComponent("source.app"),
                journal: root.appendingPathComponent("journal.json"), mode: .on, previousMode: .off,
                validate: validate, stopped: {}, copy: copy,
                afterOriginalMoved: { throw CocoaError(.fileWriteUnknown) }
            )
            XCTFail("Expected injected failure")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("installed.app")), Data("off".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testRunningProtectionLeavesInstallationUntouched() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try await DictationPatchTransaction.replace(
                app: root.appendingPathComponent("installed.app"), source: root.appendingPathComponent("source.app"),
                journal: root.appendingPathComponent("journal.json"), mode: .on, previousMode: .off,
                validate: validate, stopped: { throw CocoaError(.userCancelled) }, copy: copy
            )
            XCTFail("Must refuse a running installation")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("installed.app")), Data("off".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testInvalidCandidateCannotReplaceOriginal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("source.app"))
        do {
            try await DictationPatchTransaction.replace(
                app: root.appendingPathComponent("installed.app"), source: root.appendingPathComponent("source.app"),
                journal: root.appendingPathComponent("journal.json"), mode: .on, previousMode: .off,
                validate: validate, stopped: {}, copy: copy
            )
            XCTFail("Must reject invalid candidate")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("installed.app")), Data("off".utf8))
    }

    func testRecoveryRestoresMissingInstallation() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("installed.app")
        let stage = root.appendingPathComponent(".codex-dictation-stage-test")
        let journal = root.appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: app, to: stage.appendingPathComponent("previous.app"))
        try JSONEncoder().encode(DictationPatchTransaction.Record(app: app, stage: stage, previousMode: .off))
            .write(to: journal)
        try await DictationPatchTransaction.recover(app: app, journal: journal, validate: validate, stopped: {})
        XCTAssertEqual(try Data(contentsOf: app), Data("off".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testRecoveryRefusesUnrelatedStageDirectory() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("installed.app")
        let journal = root.appendingPathComponent("journal.json")
        try JSONEncoder().encode(DictationPatchTransaction.Record(
            app: app, stage: root.appendingPathComponent("unrelated"), previousMode: .off
        )).write(to: journal)
        do {
            try await DictationPatchTransaction.recover(app: app, journal: journal, validate: validate, stopped: {})
            XCTFail("Must reject unrelated stage")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertEqual(try Data(contentsOf: app), Data("off".utf8))
    }

    func testUpdaterChangeDuringStagingIsNotOverwritten() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("installed.app")
        do {
            try await DictationPatchTransaction.replace(
                app: app, source: root.appendingPathComponent("source.app"),
                journal: root.appendingPathComponent("journal.json"), mode: .on, previousMode: .off,
                validate: validate, stopped: {}, copy: { source, target in
                    try FileManager.default.copyItem(at: source, to: target)
                    try Data("updated installation".utf8).write(to: app)
                }
            )
            XCTFail("Must refuse installation changes during staging")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: app), Data("updated installation".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testRecoveryDoesNotOverwriteUnknownCurrentInstallation() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("installed.app")
        let stage = root.appendingPathComponent(".codex-dictation-stage-test")
        let journal = root.appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: app, to: stage.appendingPathComponent("previous.app"))
        try Data("updated".utf8).write(to: app)
        try JSONEncoder().encode(DictationPatchTransaction.Record(app: app, stage: stage, previousMode: .off))
            .write(to: journal)
        do {
            try await DictationPatchTransaction.recover(app: app, journal: journal, validate: validate, stopped: {})
            XCTFail("Must not overwrite an unrelated installation")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: app), Data("updated".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("previous.app").path))
    }

    func testPendingJournalIsNotOverwrittenByNewTransaction() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("journal.json")
        let pending = Data("pending recovery".utf8)
        try pending.write(to: journal)
        do {
            try await DictationPatchTransaction.replace(
                app: root.appendingPathComponent("installed.app"), source: root.appendingPathComponent("source.app"),
                journal: journal, mode: .on, previousMode: .off,
                validate: validate, stopped: {}, copy: copy
            )
            XCTFail("Must preserve pending recovery")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: journal), pending)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("installed.app")), Data("off".utf8))
    }

    func testFingerprintPinnedRecoveryRestoresUnknownPreviousBundle() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Installed.app")
        let stage = root.appendingPathComponent(".codex-dictation-stage-pinned")
        let previous = stage.appendingPathComponent("previous.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("unknown prior modifications".utf8).write(to: app.appendingPathComponent("content"))
        let original = try DictationPatchTransaction.fingerprint(app)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        try fm.moveItem(at: app, to: previous)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("verified candidate".utf8).write(to: app.appendingPathComponent("content"))
        let next = try DictationPatchTransaction.fingerprint(app)
        let journal = root.appendingPathComponent("journal.json")
        try JSONEncoder().encode(DictationPatchTransaction.Record(app: app, stage: stage, previousMode: .unknown,
            previousFingerprint: original, candidateFingerprint: next)).write(to: journal)
        try await DictationPatchTransaction.recover(app: app, journal: journal, validate: { _, _ in }, stopped: {})
        XCTAssertEqual(try DictationPatchTransaction.fingerprint(app), original)
        XCTAssertFalse(fm.fileExists(atPath: journal.path))
    }

    func testPinnedRecoveryRefusesChangedCandidateEvenIfValidatorAcceptsIt() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Installed.app")
        let stage = root.appendingPathComponent(".codex-dictation-stage-pinned")
        let previous = stage.appendingPathComponent("previous.app")
        try fm.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: previous.appendingPathComponent("content"))
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("candidate".utf8).write(to: app.appendingPathComponent("content"))
        let original = try DictationPatchTransaction.fingerprint(previous)
        let candidate = try DictationPatchTransaction.fingerprint(app)
        let journal = root.appendingPathComponent("journal.json")
        try JSONEncoder().encode(DictationPatchTransaction.Record(app: app, stage: stage, previousMode: .unknown,
            previousFingerprint: original, candidateFingerprint: candidate)).write(to: journal)
        try Data("unrelated update".utf8).write(to: app.appendingPathComponent("content"))
        do {
            try await DictationPatchTransaction.recover(app: app, journal: journal, validate: { _, _ in }, stopped: {})
            XCTFail("An unrelated installation must never be overwritten")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("content")), Data("unrelated update".utf8))
        XCTAssertTrue(fm.fileExists(atPath: journal.path))
    }

    func testBundleFingerprintIsStableAcrossCopiesAndDirectoryEnumerationOrder() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Original.app")
        try fm.createDirectory(at: app.appendingPathComponent("Versions/A/nested"), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: app.appendingPathComponent("Versions/A/nested/file"))
        try fm.createSymbolicLink(atPath: app.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try Data("other".utf8).write(to: app.appendingPathComponent("z-file"))
        let destination = root.appendingPathComponent("Copy.app")
        try await LegacyDictationPatchService(installedApp: app, storageDirectory: root).copy(app, destination)
        XCTAssertEqual(try DictationPatchTransaction.fingerprint(app), try DictationPatchTransaction.fingerprint(destination))
        try Data("changed".utf8).write(to: destination.appendingPathComponent("Versions/A/nested/file"))
        XCTAssertNotEqual(try DictationPatchTransaction.fingerprint(app), try DictationPatchTransaction.fingerprint(destination))
    }
}
