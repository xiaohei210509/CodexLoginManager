import Foundation

struct LegacyDictationPatchService: Sendable {
    let installedApp: URL
    let storageDirectory: URL
    private let runner = ProcessRunner()

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexLoginManager/DictationPatch", isDirectory: true)
    }

    init(installedApp: URL? = nil, storageDirectory: URL = Self.defaultDirectory) {
        let fm = FileManager.default
        let candidates = ["/Applications/ChatGPT.app", "/Applications/Codex.app",
                          fm.homeDirectoryForCurrentUser.path + "/Applications/ChatGPT.app",
                          fm.homeDirectoryForCurrentUser.path + "/Applications/Codex.app"]
        let recorded = try? JSONDecoder().decode(DictationPatchTransaction.Record.self,
            from: Data(contentsOf: storageDirectory.appendingPathComponent("transaction.json"))).app
        let allowedRecoveryPaths = candidates.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let recoveryApp = recorded.flatMap { allowedRecoveryPaths.contains($0.path) ? $0 : nil }
        self.installedApp = (installedApp ?? recoveryApp ?? URL(fileURLWithPath:
            candidates.first { fm.fileExists(atPath: $0 + "/Contents/Resources/app.asar") }
                ?? candidates[0])).resolvingSymlinksInPath()
        self.storageDirectory = storageDirectory
    }

    private var backup: URL { storageDirectory.appendingPathComponent("official.app") }
    private var patched: URL { storageDirectory.appendingPathComponent("patched.app") }
    private var journal: URL { storageDirectory.appendingPathComponent("transaction.json") }
    private func archive(_ app: URL) -> URL { app.appendingPathComponent("Contents/Resources/app.asar") }
    private func framework(_ app: URL) -> URL {
        app.appendingPathComponent("Contents/Frameworks/Codex Framework.framework/Codex Framework")
    }

    func execute(_ command: DictationPatchCommand) async throws -> DictationPatchResponse {
        try await Task.detached(priority: .utility) {
            let recipe = try DictationPatchRecipe.bundled()
            var failure: DictationPatchResponse.Failure?
            var log = ""
            do {
                if command != .status {
                    let lock = try DictationPatchLock(directory: storageDirectory)
                    defer { withExtendedLifetime(lock) {} }
                    try await assertStopped()
                    if command == .recover {
                        try await DictationPatchTransaction.recover(
                            app: installedApp, journal: journal,
                            validate: { try await verify($0, mode: $1, recipe: recipe) },
                            stopped: assertStopped
                        )
                    } else {
                        try require(!FileManager.default.fileExists(atPath: journal.path), "patch.recovery_required")
                        let state = try identify(installedApp, recipe: recipe)
                        try require(state == .off || state == .on, "patch.unsupported")
                        let desired: DictationPatchState = command == .on ? .on : .off
                        try await verify(installedApp, mode: state, recipe: recipe)
                        if desired != state {
                            if desired == .on { try await prepare(recipe) }
                            let source = desired == .on ? patched : backup
                            try await verify(source, mode: desired, recipe: recipe)
                            try await DictationPatchTransaction.replace(
                                app: installedApp, source: source, journal: journal,
                                mode: desired, previousMode: state,
                                validate: { try await verify($0, mode: $1, recipe: recipe) },
                                stopped: assertStopped, copy: copy
                            )
                        }
                    }
                    log = L10n.text("patch.completed")
                }
            } catch {
                failure = .init(message: error.localizedDescription)
            }
            let status = try await snapshot(recipe)
            return DictationPatchResponse(schemaVersion: 1, ok: failure == nil, status: status,
                                           log: log, error: failure)
        }.value
    }

    private func identify(_ app: URL, recipe: DictationPatchRecipe) throws -> DictationPatchState {
        guard FileManager.default.fileExists(atPath: app.path) else { return .missing }
        guard FileManager.default.fileExists(atPath: archive(app).path) else { return .unknown }
        switch try DictationPatchRecipe.fileSHA(archive(app)) {
        case recipe.originalArchiveSha256: return .off
        case recipe.patchedArchiveSha256: return .on
        default: return .unknown
        }
    }

    private func plist(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
        }
        return dictionary
    }

    private func snapshot(_ recipe: DictationPatchRecipe) async throws -> DictationPatchStatus {
        let fm = FileManager.default
        return DictationPatchStatus(
            state: try identify(installedApp, recipe: recipe), installedApp: installedApp.path,
            installedVersion: (try? plist(installedApp))?["CFBundleShortVersionString"] as? String,
            supportedVersion: recipe.version, runningProcessCount: try await runningCount(),
            recoveryRequired: fm.fileExists(atPath: journal.path),
            officialBackupAvailable: (try? identify(backup, recipe: recipe)) == .off,
            patchedArtifactAvailable: (try? identify(patched, recipe: recipe)) == .on,
            installationWritable: fm.isWritableFile(atPath: installedApp.deletingLastPathComponent().path),
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func runningCount() async throws -> Int {
        let result = try await run("/bin/ps", ["-axo", "pid=,comm="])
        let prefix = installedApp.path + "/Contents/"
        return result.stdout.split(separator: "\n").filter { line in
            let fields = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { return false }
            let executable = String(fields[1])
            return executable.hasPrefix(prefix)
                && !executable.hasSuffix("/browser_crashpad_handler")
        }.count
    }

    func assertStopped() async throws {
        try require(try await runningCount() == 0, "patch.running_warning")
    }

    private func verify(_ app: URL, mode: DictationPatchState, recipe: DictationPatchRecipe) async throws {
        try require(app.resolvingSymlinksInPath().path == app.path)
        try require(try identify(app, recipe: recipe) == mode)
        let info = try plist(app)
        try require(info["CFBundleShortVersionString"] as? String == recipe.version)
        _ = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        if mode == .off {
            let signing = try await run("/usr/bin/codesign", ["-dvv", app.path])
            try require(signing.stderr.contains("TeamIdentifier=2DC432GLL2") &&
                        signing.stderr.contains("Authority=Developer ID Application: OpenAI OpCo, LLC"))
            try require(try DictationPatchRecipe.fileSHA(framework(app)) == recipe.originalFrameworkSha256)
        } else {
            try recipe.frameworkSlot(framework(app), digest: recipe.patchedDigest)
        }
        let integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]]
        try require(integrity?["Resources/app.asar"]?["hash"] ==
                    (mode == .on ? recipe.patchedHeaderSha256 : recipe.originalHeaderSha256))
    }

    func copy(_ source: URL, _ target: URL) async throws {
        try require(!FileManager.default.fileExists(atPath: target.path))
        _ = try await run("/usr/bin/ditto", [source.path, target.path])
        _ = try await run("/usr/bin/xattr", ["-crs", target.path])
    }

    private func prepare(_ recipe: DictationPatchRecipe) async throws {
        let fm = FileManager.default
        try await verify(installedApp, mode: .off, recipe: recipe)
        if fm.fileExists(atPath: backup.path) {
            try await verify(backup, mode: .off, recipe: recipe)
        } else {
            let temporary = storageDirectory.appendingPathComponent("backup-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: temporary) }
            try await copy(installedApp, temporary)
            try await verify(temporary, mode: .off, recipe: recipe)
            try fm.moveItem(at: temporary, to: backup)
        }
        if fm.fileExists(atPath: patched.path) {
            if (try? await verify(patched, mode: .on, recipe: recipe)) != nil { return }
            try fm.removeItem(at: patched)
        }
        let temporary = storageDirectory.appendingPathComponent("prepare-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: temporary) }
        try await copy(backup, temporary)
        let archiveURL = archive(temporary)
        try require(archiveURL.resolvingSymlinksInPath().path.hasPrefix(temporary.path + "/"))
        let bytes = try Data(contentsOf: archiveURL)
        try recipe.patchArchive(bytes).write(to: archiveURL, options: .atomic)
        var info = try plist(temporary)
        guard var integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]] else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
        }
        integrity["Resources/app.asar"]?["hash"] = recipe.patchedHeaderSha256
        info["ElectronAsarIntegrity"] = integrity
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: temporary.appendingPathComponent("Contents/Info.plist"), options: .atomic)
        let native = framework(temporary).resolvingSymlinksInPath()
        try require(native.path.hasPrefix(temporary.path + "/"))
        try require(try DictationPatchRecipe.fileSHA(native) == recipe.originalFrameworkSha256)
        try recipe.frameworkSlot(native, digest: recipe.originalDigest)
        let handle = try FileHandle(forWritingTo: native)
        do {
            try handle.seek(toOffset: recipe.slotOffset + 34)
            let digest = stride(from: 0, to: recipe.patchedDigest.count, by: 2).map { offset -> UInt8 in
                let start = recipe.patchedDigest.index(recipe.patchedDigest.startIndex, offsetBy: offset)
                let end = recipe.patchedDigest.index(start, offsetBy: 2)
                return UInt8(recipe.patchedDigest[start..<end], radix: 16)!
            }
            try handle.write(contentsOf: Data(digest))
            try handle.synchronize()
            try handle.close()
        } catch { try? handle.close(); throw error }
        try require(try DictationPatchRecipe.fileSHA(native) == recipe.patchedUnsignedFrameworkSha256)
        try await sign(temporary)
        try await verify(temporary, mode: .on, recipe: recipe)
        try fm.moveItem(at: temporary, to: patched)
    }

    func sign(_ app: URL) async throws {
        let fm = FileManager.default
        let frameworkURL = app.appendingPathComponent("Contents/Frameworks/Codex Framework.framework")
        let helpers = frameworkURL.appendingPathComponent("Helpers").resolvingSymlinksInPath()
        try require(helpers.path.hasPrefix(app.path + "/"))
        let apps = try fm.contentsOfDirectory(at: helpers, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }.sorted { $0.path < $1.path }
        try require(!apps.isEmpty)
        for helper in apps { try await signExecutable(helper, entitlements: true) }
        try await signExecutable(frameworkURL, entitlements: false)
        try await signExecutable(app, entitlements: true)
    }

    private func signExecutable(_ artifact: URL, entitlements: Bool) async throws {
        var arguments = ["--force", "--sign", "-", "--options", "runtime", "--timestamp=none"]
        let temporary = storageDirectory.appendingPathComponent("entitlements-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if entitlements {
            let result = try await run("/usr/bin/codesign", ["-d", "--entitlements", ":-", artifact.path])
            var value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [:] : try PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil) as? [String: Any] ?? [:]
            for key in ["com.apple.application-identifier", "com.apple.developer.team-identifier",
                        "com.apple.developer.aps-environment", "com.apple.developer.usernotifications.communication",
                        "com.apple.security.application-groups", "keychain-access-groups"] {
                value.removeValue(forKey: key)
            }
            value["com.apple.security.cs.disable-library-validation"] = true
            try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: temporary)
            arguments += ["--entitlements", temporary.path]
        }
        _ = try await run("/usr/bin/codesign", arguments + [artifact.path])
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        let result = try await runner.run(executablePath: executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw DictationPatchError.executionFailed(Redactor.sanitize(result.combinedOutput))
        }
        return result
    }
}
