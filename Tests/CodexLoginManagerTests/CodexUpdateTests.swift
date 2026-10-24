import CryptoKit
import XCTest
@testable import CodexLoginManager

final class CodexUpdateTests: XCTestCase, @unchecked Sendable {
    static func update(version: String = "26.1021.22027", build: String = "21747",
                       signature: Data = Data(repeating: 0, count: 64), length: Int64 = 1) -> CodexUpdate {
        CodexUpdate(version: version, build: build, minimumSystemVersion: "13.0", architecture: "arm64",
            url: URL(string: "https://persistent.oaistatic.com/codex-app-prod/test.zip")!,
            length: length, signature: signature)
    }

    private func feed(arch: String = "arm64", minimum: String = "13.0", url: String = "https://persistent.oaistatic.com/codex-app-prod/test.zip") -> Data {
        Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>21747</sparkle:version>
        <sparkle:shortVersionString>26.1021.22027</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>\(minimum)</sparkle:minimumSystemVersion>
        <sparkle:hardwareRequirements>\(arch)</sparkle:hardwareRequirements>
        <enclosure url="\(url)" length="123" sparkle:edSignature="\(Data(repeating: 0, count: 64).base64EncodedString())"/>
        <sparkle:deltas><enclosure url="https://untrusted.invalid/unsafe.delta" sparkle:deltaFrom="21161"/></sparkle:deltas>
        </item></channel></rss>
        """.utf8)
    }

    func testUpdateRequestAlwaysUsesPlusAndStableChannel() throws {
        let installationID = UUID()
        let url = CodexUpdateService.appcastURL(version: "26.1016.51333", systemVersion: "26.0",
            installationID: installationID)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "updates.oaistatic.com")
        XCTAssertEqual(components.path, "/codex/app/appcast")
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items.filter { $0.name == "plan_type" }.map(\.value), ["plus"])
        XCTAssertEqual(items.filter { $0.name == "beta" }.map(\.value), ["false"])
        XCTAssertEqual(items.first { $0.name == "app_version" }?.value, "26.1016.51333")
        XCTAssertEqual(items.first { $0.name == "os-version" }?.value, "26.0")
        XCTAssertEqual(items.first { $0.name == "arch" }?.value, CodexUpdate.architecture)
        XCTAssertEqual(items.first { $0.name == "installation_id" }?.value, installationID.uuidString)
    }

    func testFeedSelectsFullArchiveAndIgnoresDeltas() throws {
        let updates = try CodexAppcastParser.parse(feed(), architecture: "arm64", systemVersion: "26.0")
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.length, 123)
        XCTAssertEqual(updates.first?.build, "21747")
        XCTAssertTrue(updates.first?.isNewer(version: "26.1016.51333", build: "21161") == true)
        XCTAssertEqual(try CodexAppcastParser.parse(feed(arch: "x64"), architecture: "arm64", systemVersion: "26.0"), [])
        XCTAssertEqual(try CodexAppcastParser.parse(feed(minimum: "27"), architecture: "arm64", systemVersion: "26.0"), [])
    }

    func testRejectsMalformedUntrustedAndEntityFeeds() {
        for data in [Data(), Data("<rss>".utf8), Data("<html/>".utf8), Data("<!DOCTYPE rss><rss/>".utf8),
                     feed(url: "http://persistent.oaistatic.com/codex-app-prod/test.zip"),
                     feed(url: "https://evil.example/test.zip")] {
            XCTAssertThrowsError(try CodexAppcastParser.parse(data, architecture: "arm64", systemVersion: "26"))
        }
    }

    func testURLAndVersionPolicyPreventsRedirectEscapeAndDowngrades() {
        for url in ["https://persistent.oaistatic.com.evil.example/codex-app-prod/test.zip",
                    "https://user@persistent.oaistatic.com/codex-app-prod/test.zip",
                    "https://persistent.oaistatic.com/other/test.zip",
                    "https://persistent.oaistatic.com:444/codex-app-prod/test.zip",
                    "http://persistent.oaistatic.com/codex-app-prod/test.zip"] {
            XCTAssertFalse(CodexUpdate.allowedURL(URL(string: url)!))
        }
        XCTAssertTrue(CodexUpdate.allowedURL(URL(string: "https://persistent.oaistatic.com/codex-app-prod/appcast-26.xml")!, feed: true))
        XCTAssertEqual(CodexUpdate.compare("26.10", "26.9"), .orderedDescending)
        XCTAssertEqual(CodexUpdate.compare("26.0", "26"), .orderedSame)
        XCTAssertNil(CodexUpdate.compare("26.beta", "26"))
        XCTAssertFalse(Self.update().isNewer(version: "26.1021.22027", build: "21747"))
        XCTAssertFalse(Self.update().isNewer(version: "26.1022.1", build: "21748"))
        XCTAssertFalse(Self.update(version: "25.1", build: "99999").isNewer(version: "26.1", build: "1"))
    }

    func testArchiveSignatureAndLengthMustBothMatchBeforeExtraction() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let bytes = Data("authenticated archive fixture".utf8)
        try bytes.write(to: temporary)
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(for: bytes)
        let update = Self.update(signature: signature, length: Int64(bytes.count))
        XCTAssertNoThrow(try CodexUpdateService.verifyArchive(temporary, update: update,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()))
        XCTAssertThrowsError(try CodexUpdateService.verifyArchive(temporary, update: update))
        XCTAssertThrowsError(try CodexUpdateService.verifyArchive(temporary,
            update: Self.update(signature: signature, length: 1),
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()))
        try Data("tampered archive".utf8).write(to: temporary)
        XCTAssertThrowsError(try CodexUpdateService.verifyArchive(temporary, update: update,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()))
    }

    func testNewestOfficialArchiveAndCrossVersionUpdateWhenExplicitlyProvided() async throws {
        guard let zip = ProcessInfo.processInfo.environment["CODEX_UPDATE_OFFICIAL_ARCHIVE"],
              let old = ProcessInfo.processInfo.environment["CODEX_PATCH_OFFICIAL_FIXTURE"] else {
            throw XCTSkip("Provide official ZIP and old app fixtures for isolated update verification.")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Installed.app")
        let io = LegacyDictationPatchService(installedApp: app, storageDirectory: root.appendingPathComponent("storage"))
        try await io.copy(URL(fileURLWithPath: old), app)
        let patch = DictationPatchService(installedApp: app, storageDirectory: io.storageDirectory)
        let enabled = try await patch.execute(.on)
        XCTAssertTrue(enabled.ok, enabled.error?.message ?? "")
        let update = Self.update(signature: Data(base64Encoded: "37w35Ra0xIP4B+lZ8J3vBGIDLF6Wk6FfaXRsKo+O7rv4OTXJLKEMCnPZ3j840BVzzm/JxSkQQYa9I63H6JgPDQ==")!,
                                 length: 750413976)
        let service = CodexUpdateService(patch: patch)
        let candidate = try await service.extractVerifiedArchive(URL(fileURLWithPath: zip), update: update, directory: root)
        let fingerprint = try DictationPatchTransaction.fingerprint(app)
        let warning = try await service.install(candidate, update: update, expectedFingerprint: fingerprint, reapply: true)
        XCTAssertNil(warning, warning ?? "")
        let status = try await patch.execute(.status)
        XCTAssertEqual(status.status?.installedVersion, update.version)
        XCTAssertEqual(status.status?.state, .on)
        let disabled = try await patch.execute(.off)
        XCTAssertTrue(disabled.ok, disabled.error?.message ?? "")
        XCTAssertEqual(disabled.status?.installedVersion, update.version)
        XCTAssertEqual(disabled.status?.state, .off)
        try await service.validate(app, update: update)
        XCTAssertEqual(try DictationPatchRecipe.fileSHA(patch.archive(app)),
                       try DictationPatchRecipe.fileSHA(patch.archive(candidate)))
        // Disabling after an upgrade restores this build, never the old backup.
        XCTAssertNotEqual(try DictationPatchRecipe.fileSHA(patch.archive(app)),
                          try DictationPatchRecipe.fileSHA(patch.archive(URL(fileURLWithPath: old))))

        let fallbackApp = root.appendingPathComponent("Fallback.app")
        try await io.copy(URL(fileURLWithPath: old), fallbackApp)
        let fallbackPatch = DictationPatchService(installedApp: fallbackApp,
            storageDirectory: root.appendingPathComponent("fallback-storage"))
        let fallbackService = CodexUpdateService(patch: fallbackPatch)
        let fallbackWarning = try await fallbackService.install(candidate, update: update,
            expectedFingerprint: DictationPatchTransaction.fingerprint(fallbackApp), reapply: true,
            applyPatch: { throw AdaptivePatchFailure.incompatible })
        XCTAssertNotNil(fallbackWarning)
        try await fallbackService.validate(fallbackApp, update: update)
        XCTAssertFalse(fm.fileExists(atPath: fallbackPatch.journal.path))
    }

    func testLiveOfficialUpdateCheckWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_UPDATE_CHECK_NETWORK"] == "1",
              let app = ProcessInfo.processInfo.environment["CODEX_PATCH_OFFICIAL_FIXTURE"] else {
            throw XCTSkip("Enable the explicit official network check to test the live appcast.")
        }
        let service = CodexUpdateService(patch: .init(installedApp: URL(fileURLWithPath: app)))
        let result = try await service.check()
        let update = try XCTUnwrap(result)
        XCTAssertTrue(update.isNewer(version: "26.1016.51333", build: "21161"))
    }
}

@MainActor
final class CodexUpdateViewModelTests: XCTestCase {
    private actor Offers {
        var count = 0
        func next() throws -> CodexUpdate? {
            defer { count += 1 }
            if count == 0 { return CodexUpdateTests.update() }
            if count == 1 { return nil }
            throw CodexUpdateFailure.invalidFeed
        }
    }

    func testPreviousUpdateOfferDisappearsWhenFeedHasNoUpdateOrFails() async {
        let offers = Offers()
        let service = DictationPatchService(installedApp: URL(fileURLWithPath: "/tmp/nonexistent-codex-fixture.app"))
        let model = DictationPatchViewModel(service: service, checkUpdates: { try await offers.next() })
        await model.refreshUpdate()
        XCTAssertNotNil(model.availableUpdate)
        await model.refreshUpdate()
        XCTAssertNil(model.availableUpdate)
        XCTAssertNil(model.updateErrorMessage)
        await model.refreshUpdate()
        XCTAssertNil(model.availableUpdate)
        XCTAssertNotNil(model.updateErrorMessage)
    }

    func testUpdateButtonPolicyHidesWhenNoUpdateOrCheckFails() async {
        let service = DictationPatchService(installedApp: URL(fileURLWithPath: "/tmp/nonexistent-codex-fixture.app"))
        let noUpdate = DictationPatchViewModel(service: service, checkUpdates: { nil })
        await noUpdate.refreshUpdate()
        XCTAssertNil(noUpdate.availableUpdate)
        XCTAssertFalse(noUpdate.canUpdate)
        XCTAssertNil(noUpdate.updateErrorMessage)
        let available = DictationPatchViewModel(service: service, checkUpdates: { CodexUpdateTests.update() })
        await available.refreshUpdate()
        XCTAssertNotNil(available.availableUpdate)
        XCTAssertFalse(available.canUpdate, "Missing installation must never be actionable")
        let failing = DictationPatchViewModel(service: service, checkUpdates: { throw CodexUpdateFailure.invalidFeed })
        await failing.refreshUpdate()
        XCTAssertNil(failing.availableUpdate)
        XCTAssertNotNil(failing.updateErrorMessage)
    }
}
