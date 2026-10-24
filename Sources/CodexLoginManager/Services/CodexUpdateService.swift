import CryptoKit
import Foundation

struct CodexUpdateService: Sendable {
    let patch: DictationPatchService
    static let publicKey = "mNfr1v9t63BfgDtlw4C8lRvSY6uMggIXABDOCi3tS6k="

    init(patch: DictationPatchService = .init()) { self.patch = patch }

    func check() async throws -> CodexUpdate? {
        let info = try AdaptivePatchPlan.info(patch.installedApp)
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              CodexUpdate.numbers(version) != nil, CodexUpdate.numbers(build) != nil else {
            throw CodexUpdateFailure.wrongVersion
        }
        let defaults = UserDefaults.standard
        let key = "CodexUpdate.managerInstallationID"
        let installationID = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(installationID.uuidString, forKey: key)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let url = Self.appcastURL(version: version, systemVersion: systemVersion, installationID: installationID)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xml")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let status = try await CodexDownload(destination: temporary, limit: 2_000_000, feed: true).download(url)
        if status == 204 { return nil }
        let updates = try CodexAppcastParser.parse(Data(contentsOf: temporary),
            architecture: CodexUpdate.architecture, systemVersion: systemVersion)
        return updates.filter { $0.isNewer(version: version, build: build) }
            .max { CodexUpdate.compare($0.build, $1.build) == .orderedAscending }
    }

    static func appcastURL(version: String, systemVersion: String, installationID: UUID) -> URL {
        var url = URLComponents(string: "https://updates.oaistatic.com/codex/app/appcast")!
        url.queryItems = [
            .init(name: "arch", value: CodexUpdate.architecture), .init(name: "app_version", value: version),
            .init(name: "beta", value: "false"), .init(name: "os-version", value: systemVersion),
            .init(name: "installation_id", value: installationID.uuidString), .init(name: "plan_type", value: "plus")
        ]
        return url.url!
    }

    static func verifyArchive(_ url: URL, update: CodexUpdate, publicKey: String = Self.publicKey) throws {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count == update.length, let key = Data(base64Encoded: publicKey),
              let verifier = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              verifier.isValidSignature(update.signature, for: bytes) else {
            throw CodexUpdateFailure.invalidSignature
        }
    }

    func prepare(_ update: CodexUpdate, directory: URL,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let zip = directory.appendingPathComponent("official.zip")
        _ = try await CodexDownload(destination: zip, limit: update.length, progress: progress).download(update.url)
        try Task.checkCancellation()
        return try await extractVerifiedArchive(zip, update: update, directory: directory)
    }

    func extractVerifiedArchive(_ zip: URL, update: CodexUpdate, directory: URL) async throws -> URL {
        try Self.verifyArchive(zip, update: update)
        try Task.checkCancellation()
        let extracted = directory.appendingPathComponent("extracted")
        let result = try await ProcessRunner().run(executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", zip.path, extracted.path])
        try require(result.exitCode == 0, "update.error.invalidDownload")
        let apps = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw CodexUpdateFailure.invalidDownload }
        try require(try apps[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
        let app = apps[0].resolvingSymlinksInPath()
        try await validate(app, update: update)
        return app
    }

    func validate(_ app: URL, update: CodexUpdate) async throws {
        try await patch.verifyOfficial(app)
        let info = try AdaptivePatchPlan.info(app)
        guard info["CFBundleShortVersionString"] as? String == update.version,
              info["CFBundleVersion"] as? String == update.build else { throw CodexUpdateFailure.wrongVersion }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        guard update.architecture == CodexUpdate.architecture,
              let minimum = info["LSMinimumSystemVersion"] as? String,
              let comparison = CodexUpdate.compare(systemVersion, minimum), comparison != .orderedAscending,
              let advertised = CodexUpdate.compare(systemVersion, update.minimumSystemVersion),
              advertised != .orderedAscending else { throw CodexUpdateFailure.wrongVersion }
        guard let name = info["CFBundleExecutable"] as? String, !name.contains("/"), !name.isEmpty else {
            throw CodexUpdateFailure.wrongVersion
        }
        let binary = try Data(contentsOf: app.appendingPathComponent("Contents/MacOS/" + name), options: .mappedIfSafe)
        let expected: UInt32 = update.architecture == "arm64" ? 0x0100000c : 0x01000007
        let magic = try binary.integer32(at: 0, bigEndian: true)
        var types: [UInt32] = []
        if magic == 0xcafebabe || magic == 0xcafebabf {
            let count = Int(try binary.integer32(at: 4, bigEndian: true))
            try require(count > 0 && count <= 16)
            types = try (0..<count).map {
                try binary.integer32(at: 8 + $0 * (magic == 0xcafebabe ? 20 : 32), bigEndian: true)
            }
        } else if try binary.integer32(at: 0) == 0xfeedfacf {
            types = [try binary.integer32(at: 4)]
        }
        try require(types.contains(expected), "update.error.wrongVersion")
    }

    // Called only after download verification and a successful graceful quit.
    func install(_ candidate: URL, update: CodexUpdate, expectedFingerprint: String,
                 reapply: Bool, applyPatch: (@Sendable () async throws -> Void)? = nil) async throws -> String? {
        let lock = try DictationPatchLock(directory: patch.storageDirectory)
        defer { withExtendedLifetime(lock) {} }
        let io = LegacyDictationPatchService(installedApp: patch.installedApp, storageDirectory: patch.storageDirectory)
        try await io.assertStopped()
        try require(!FileManager.default.fileExists(atPath: patch.journal.path), "patch.recovery_required")
        try await validate(candidate, update: update)
        let info = try AdaptivePatchPlan.info(patch.installedApp)
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String, update.isNewer(version: version, build: build),
              try DictationPatchTransaction.fingerprint(patch.installedApp) == expectedFingerprint else {
            throw CodexUpdateFailure.changedInstallation
        }
        let nextFingerprint = try DictationPatchTransaction.fingerprint(candidate)
        let backup = patch.storageDirectory.appendingPathComponent("update-backups/\(UUID().uuidString).app")
        try require(backup.deletingLastPathComponent().resolvingSymlinksInPath().path == backup.deletingLastPathComponent().path)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await io.copy(patch.installedApp, backup)
        try require(try DictationPatchTransaction.fingerprint(backup) == expectedFingerprint)
        try Task.checkCancellation()
        try await DictationPatchTransaction.replace(
            app: patch.installedApp, source: candidate, journal: patch.journal, mode: .off, previousMode: .unknown,
            validate: { app, mode in
                if mode == .off { try await validate(app, update: update) }
            }, stopped: io.assertStopped, copy: io.copy,
            previousFingerprint: expectedFingerprint, candidateFingerprint: nextFingerprint)
        guard reapply else { return nil }
        do {
            if let applyPatch { try await applyPatch() }
            else { try await patch.switchPatch(true) }
            return nil
        } catch {
            if FileManager.default.fileExists(atPath: patch.journal.path) { throw error }
            return L10n.text("update.patch_skipped") + "\n" + error.localizedDescription
        }
    }
}
