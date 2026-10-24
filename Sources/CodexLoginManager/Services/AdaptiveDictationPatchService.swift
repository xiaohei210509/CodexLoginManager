import Foundation

struct DictationPatchService: Sendable {
    let installedApp: URL
    let storageDirectory: URL
    static var defaultDirectory: URL { LegacyDictationPatchService.defaultDirectory }

    init(installedApp: URL? = nil, storageDirectory: URL = Self.defaultDirectory) {
        self.installedApp = LegacyDictationPatchService(installedApp: installedApp,
                                                       storageDirectory: storageDirectory).installedApp
        self.storageDirectory = storageDirectory
    }

    var journal: URL { storageDirectory.appendingPathComponent("transaction.json") }
    private var legacy: LegacyDictationPatchService {
        LegacyDictationPatchService(installedApp: installedApp, storageDirectory: storageDirectory)
    }
    private var builds: URL { storageDirectory.appendingPathComponent("builds") }
    private var preference: URL { storageDirectory.appendingPathComponent("desired-patch.json") }
    func directory(_ plan: AdaptivePatchPlan) -> URL { builds.appendingPathComponent(plan.key) }
    func archive(_ app: URL) -> URL { app.appendingPathComponent("Contents/Resources/app.asar") }
    private func framework(_ app: URL) -> URL {
        app.appendingPathComponent("Contents/Frameworks/Codex Framework.framework/Codex Framework")
    }

    var desiresPatch: Bool {
        (try? JSONDecoder().decode(Bool.self, from: Data(contentsOf: preference))) == true
    }

    func execute(_ command: DictationPatchCommand) async throws -> DictationPatchResponse {
        try await Task.detached(priority: .utility) {
            // Preserve restoration for installations created by the previous embedded engine.
            let recipe = try DictationPatchRecipe.bundled()
            if (try? DictationPatchRecipe.fileSHA(archive(installedApp))) == recipe.patchedArchiveSha256 {
                let result = try await legacy.execute(command)
                if result.ok && command == .off { try savePreference(false) }
                return result
            }
            if command == .recover,
               let record = try? JSONDecoder().decode(DictationPatchTransaction.Record.self, from: Data(contentsOf: journal)),
               record.previousFingerprint == nil {
                return try await legacy.execute(command)
            }
            var failure: DictationPatchResponse.Failure?
            do {
                if command != .status {
                    let lock = try DictationPatchLock(directory: storageDirectory)
                    defer { withExtendedLifetime(lock) {} }
                    try await legacy.assertStopped()
                    if command == .recover {
                        try await DictationPatchTransaction.recover(
                            app: installedApp, journal: journal,
                            validate: { app, state in
                                if state != .unknown { try await verifyKnown(app, state: state) }
                            }, stopped: legacy.assertStopped)
                    } else {
                        try await switchPatch(command == .on)
                        try savePreference(command == .on)
                    }
                }
            } catch { failure = .init(message: error.localizedDescription) }
            return DictationPatchResponse(schemaVersion: 1, ok: failure == nil, status: try await snapshot(),
                log: command == .status || failure != nil ? "" : L10n.text("patch.completed"), error: failure)
        }.value
    }

    private func savePreference(_ enabled: Bool) throws {
        try JSONEncoder().encode(enabled).write(to: preference, options: .atomic)
    }

    func verifyOfficial(_ app: URL) async throws {
        _ = try AdaptivePatchPlan.info(app)
        try require(app.resolvingSymlinksInPath().path == app.path)
        let result = try await ProcessRunner().run(executablePath: "/usr/bin/codesign",
                                                 arguments: ["--verify", "--deep", "--strict", app.path])
        guard result.exitCode == 0 else {
            throw DictationPatchError.executionFailed(Redactor.sanitize(result.combinedOutput))
        }
        let signature = try await ProcessRunner().run(executablePath: "/usr/bin/codesign",
                                                     arguments: ["-dvv", app.path])
        try require(signature.exitCode == 0 && signature.stderr.contains("TeamIdentifier=2DC432GLL2") &&
                    signature.stderr.contains("Authority=Developer ID Application: OpenAI OpCo, LLC"))
    }

    func storedPlan(_ app: URL) throws -> AdaptivePatchPlan? {
        guard FileManager.default.fileExists(atPath: builds.path) else { return nil }
        let info = try AdaptivePatchPlan.info(app)
        let sha = try DictationPatchRecipe.fileSHA(archive(app))
        for name in try FileManager.default.contentsOfDirectory(atPath: builds.path) {
            let directory = builds.appendingPathComponent(name)
            guard directory.resolvingSymlinksInPath().path == directory.path,
                  let plan = try? JSONDecoder().decode(AdaptivePatchPlan.self,
                    from: Data(contentsOf: directory.appendingPathComponent("plan.json"))),
                  plan.schemaVersion == 1, plan.key == directory.lastPathComponent,
                  info["CFBundleShortVersionString"] as? String == plan.version,
                  info["CFBundleVersion"] as? String == plan.build else { continue }
            if sha == plan.patchedArchiveSha256 || sha == plan.originalArchiveSha256 { return plan }
        }
        return nil
    }

    private func resolve(_ app: URL) async -> (DictationPatchState, AdaptivePatchPlan?) {
        guard FileManager.default.fileExists(atPath: app.path) else { return (.missing, nil) }
        do {
            if let plan = try storedPlan(app) {
                let info = try AdaptivePatchPlan.info(app)
                let integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]]
                let state: DictationPatchState = integrity?["Resources/app.asar"]?["hash"] == plan.patchedHeaderSha256 ? .on : .off
                try await verify(app, state: state, plan: plan)
                return (state, plan)
            }
            try await verifyOfficial(app)
            let result = try AdaptivePatchPlan.analyze(app)
            return (.off, result.plan)
        } catch AdaptivePatchFailure.notNeeded { return (.notNeeded, nil) }
        catch { return (.unknown, nil) }
    }

    func verifyKnown(_ app: URL, state: DictationPatchState) async throws {
        if state == .off {
            try await verifyOfficial(app)
        } else {
            guard let plan = try storedPlan(app) else { throw AdaptivePatchFailure.incompatible }
            try await verify(app, state: state, plan: plan)
        }
    }

    private func verify(_ app: URL, state: DictationPatchState, plan: AdaptivePatchPlan) async throws {
        try require(state == .on || state == .off)
        let info = try AdaptivePatchPlan.info(app)
        try require(info["CFBundleShortVersionString"] as? String == plan.version &&
                    info["CFBundleVersion"] as? String == plan.build)
        try require(try DictationPatchRecipe.fileSHA(archive(app)) ==
                    (state == .on ? plan.patchedArchiveSha256 : plan.originalArchiveSha256))
        if state == .off {
            try await verifyOfficial(app)
            try require(try DictationPatchRecipe.fileSHA(framework(app)) == plan.originalFrameworkSha256)
        } else {
            let result = try await ProcessRunner().run(executablePath: "/usr/bin/codesign",
                                                     arguments: ["--verify", "--deep", "--strict", app.path])
            try require(result.exitCode == 0)
        }
        try plan.verifySlots(framework(app), patched: state == .on)
        let integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]]
        try require(integrity?["Resources/app.asar"]?["hash"] ==
                    (state == .on ? plan.patchedHeaderSha256 : plan.originalHeaderSha256))
    }

    private func snapshot() async throws -> DictationPatchStatus {
        let (state, plan) = await resolve(installedApp)
        let fm = FileManager.default
        let root = plan.map(directory)
        return DictationPatchStatus(state: state, installedApp: installedApp.path,
            installedVersion: (try? AdaptivePatchPlan.info(installedApp))?["CFBundleShortVersionString"] as? String,
            supportedVersion: plan?.version ?? L10n.text("patch.adaptive"),
            runningProcessCount: try await legacy.runningCount(),
            recoveryRequired: fm.fileExists(atPath: journal.path),
            officialBackupAvailable: root.map { fm.fileExists(atPath: $0.appendingPathComponent("official.app").path) } ?? false,
            patchedArtifactAvailable: root.map { fm.fileExists(atPath: $0.appendingPathComponent("patched.app").path) } ?? false,
            installationWritable: fm.isWritableFile(atPath: installedApp.deletingLastPathComponent().path),
            checkedAt: ISO8601DateFormatter().string(from: Date()))
    }

    // The caller owns the operation lock, including during an update followed by patching.
    func switchPatch(_ enabled: Bool) async throws {
        try require(!FileManager.default.fileExists(atPath: journal.path), "patch.recovery_required")
        let (state, existing) = await resolve(installedApp)
        if enabled && state == .notNeeded { return }
        guard let plan = existing, state == .on || state == .off else { throw AdaptivePatchFailure.incompatible }
        let desired: DictationPatchState = enabled ? .on : .off
        if state == desired { return }
        if enabled { try await prepare(plan) }
        let source = directory(plan).appendingPathComponent(enabled ? "patched.app" : "official.app")
        try await DictationPatchTransaction.replace(
            app: installedApp, source: source, journal: journal, mode: desired, previousMode: state,
            validate: { try await verify($0, state: $1, plan: plan) },
            stopped: legacy.assertStopped, copy: legacy.copy,
            previousFingerprint: try DictationPatchTransaction.fingerprint(installedApp),
            candidateFingerprint: try DictationPatchTransaction.fingerprint(source))
    }

    private func prepare(_ plan: AdaptivePatchPlan) async throws {
        try require(plan.patchedDigest.count == 64 &&
                    plan.patchedDigest.allSatisfy { $0.isASCII && $0.isHexDigit })
        let fm = FileManager.default
        let root = directory(plan)
        try require(builds.resolvingSymlinksInPath().path == builds.path)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try require(root.resolvingSymlinksInPath().path == root.path)
        let backup = root.appendingPathComponent("official.app")
        if !fm.fileExists(atPath: backup.path) {
            let pendingBackup = root.appendingPathComponent("backup-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: pendingBackup) }
            try await legacy.copy(installedApp, pendingBackup)
            try await verify(pendingBackup, state: .off, plan: plan)
            try fm.moveItem(at: pendingBackup, to: backup)
        }
        try await verify(backup, state: .off, plan: plan)
        try JSONEncoder().encode(plan).write(to: root.appendingPathComponent("plan.json"), options: .atomic)
        let patched = root.appendingPathComponent("patched.app")
        if fm.fileExists(atPath: patched.path) {
            if (try? await verify(patched, state: .on, plan: plan)) != nil { return }
            try fm.removeItem(at: patched)
        }
        let temporary = root.appendingPathComponent("prepare-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: temporary) }
        try await legacy.copy(backup, temporary)
        let result = try AdaptivePatchPlan.analyze(temporary)
        try require(result.plan.patchedArchiveSha256 == plan.patchedArchiveSha256)
        try result.archive.write(to: archive(temporary), options: .atomic)
        var info = try AdaptivePatchPlan.info(temporary)
        guard var integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]] else {
            throw AdaptivePatchFailure.incompatible
        }
        integrity["Resources/app.asar"]?["hash"] = plan.patchedHeaderSha256
        info["ElectronAsarIntegrity"] = integrity
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: temporary.appendingPathComponent("Contents/Info.plist"), options: .atomic)
        let native = framework(temporary).resolvingSymlinksInPath()
        try require(native.path.hasPrefix(temporary.path + "/"))
        let handle = try FileHandle(forWritingTo: native)
        defer { try? handle.close() }
        let digest = Data(stride(from: 0, to: plan.patchedDigest.count, by: 2).map { offset in
            let start = plan.patchedDigest.index(plan.patchedDigest.startIndex, offsetBy: offset)
            return UInt8(plan.patchedDigest[start..<plan.patchedDigest.index(start, offsetBy: 2)], radix: 16)!
        })
        for slot in plan.slots {
            try handle.seek(toOffset: slot.offset + 34)
            try handle.write(contentsOf: digest)
        }
        try handle.synchronize()
        try handle.close()
        try await legacy.sign(temporary)
        try await verify(temporary, state: .on, plan: plan)
        try fm.moveItem(at: temporary, to: patched)
    }
}
