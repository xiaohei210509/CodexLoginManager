import AppKit
import Foundation

@MainActor
final class DictationPatchViewModel: ObservableObject {
    @Published private(set) var status: DictationPatchStatus?
    @Published private(set) var isBusy = false
    @Published private(set) var activityLog = ""
    @Published private(set) var errorMessage: String?
    @Published var pendingCommand: DictationPatchCommand?
    @Published private(set) var availableUpdate: CodexUpdate?
    @Published private(set) var isCheckingUpdates = false
    @Published private(set) var updateErrorMessage: String?
    @Published private(set) var updateProgress: Double?
    @Published private(set) var updatePhase = ""
    @Published private(set) var canCancelUpdate = false
    @Published var pendingUpdate = false
    private let service: DictationPatchService
    private let checkUpdates: @Sendable () async throws -> CodexUpdate?
    private var updateTask: Task<Void, Never>?
    var storageDirectory: URL { service.storageDirectory }

    init(service: DictationPatchService = .init(),
         checkUpdates: (@Sendable () async throws -> CodexUpdate?)? = nil) {
        self.service = service
        self.checkUpdates = checkUpdates ?? { try await CodexUpdateService(patch: service).check() }
    }

    var canSwitch: Bool { status?.canSwitch == true && !isBusy }
    var canRecover: Bool { status?.canRecover == true && !isBusy }
    var canUpdate: Bool {
        availableUpdate != nil && !isBusy && status?.installationWritable == true &&
            status?.recoveryRequired == false && status?.state != .missing
    }

    func refresh() async {
        guard !isBusy else { return }
        await perform(.status)
        await refreshUpdate()
    }

    func refreshUpdate() async {
        guard !isBusy, !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateErrorMessage = nil
        defer { isCheckingUpdates = false }
        let stamp = installationStamp()
        do {
            let result = try await checkUpdates()
            guard !isBusy, stamp == installationStamp() else { availableUpdate = nil; return }
            availableUpdate = result
        } catch {
            availableUpdate = nil
            if !Task.isCancelled { updateErrorMessage = Redactor.sanitize(error.localizedDescription) }
        }
    }

    private func installationStamp() -> String? {
        guard let info = try? AdaptivePatchPlan.info(service.installedApp),
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return nil }
        return version + ":" + build
    }

    func confirmUpdate() {
        pendingUpdate = false
        guard canUpdate, let update = availableUpdate else { return }
        isBusy = true
        canCancelUpdate = true
        errorMessage = nil
        updateErrorMessage = nil
        updatePhase = L10n.text("update.downloading")
        updateProgress = 0
        updateTask = Task { await installUpdate(update) }
    }

    func cancelUpdate() {
        if canCancelUpdate { updateTask?.cancel() }
    }

    private func installUpdate(_ update: CodexUpdate) async {
        let updater = CodexUpdateService(patch: service)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUpdate-\(UUID().uuidString)")
        var didQuit = false
        defer {
            try? FileManager.default.removeItem(at: temporary)
            canCancelUpdate = false
            updateProgress = nil
            updatePhase = ""
            isBusy = false
            updateTask = nil
        }
        do {
            let service = self.service
            let fingerprint = try await Task.detached(priority: .utility) {
                try DictationPatchTransaction.fingerprint(service.installedApp)
            }.value
            let reapply = service.desiresPatch || status?.state == .on
            let candidate = try await updater.prepare(update, directory: temporary) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.canCancelUpdate else { return }
                    self.updateProgress = progress
                    if progress >= 1 { self.updatePhase = L10n.text("update.verifying") }
                }
            }
            try Task.checkCancellation()
            canCancelUpdate = false
            updateProgress = nil
            updatePhase = L10n.text("update.quitting")
            try await quitCodex()
            didQuit = true
            updatePhase = L10n.text("update.installing")
            let warning = try await Task.detached(priority: .utility) {
                try await updater.install(candidate, update: update, expectedFingerprint: fingerprint, reapply: reapply)
            }.value
            availableUpdate = nil
            activityLog = L10n.text("update.completed") + " " + update.version
            if let warning { activityLog += "\n" + Redactor.sanitize(warning) }
            if !FileManager.default.fileExists(atPath: service.journal.path) {
                NSWorkspace.shared.open(service.installedApp)
            }
            let response = try await service.execute(.status)
            status = response.status
        } catch {
            if !Task.isCancelled {
                errorMessage = Redactor.sanitize(error.localizedDescription)
            }
            if didQuit && !FileManager.default.fileExists(atPath: service.journal.path) {
                NSWorkspace.shared.open(service.installedApp)
            }
            status = try? await service.execute(.status).status
            if status?.installedVersion == update.version { availableUpdate = nil }
        }
    }

    private func quitCodex() async throws {
        let target = service.installedApp
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .filter { $0.bundleURL?.resolvingSymlinksInPath() == target }
        for app in apps {
            guard app.terminate() else { throw CodexUpdateFailure.quitFailed }
        }
        let io = LegacyDictationPatchService(installedApp: target, storageDirectory: service.storageDirectory)
        for _ in 0..<30 {
            if apps.allSatisfy(\.isTerminated), (try await io.runningCount()) == 0 { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw CodexUpdateFailure.quitFailed
    }

    func confirmCommand(_ command: DictationPatchCommand) async {
        pendingCommand = nil
        guard command == .recover ? canRecover : canSwitch else { return }
        await perform(command)
        await refreshUpdate()
    }

    func showBackupDirectory() {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageDirectory.path)
    }

    func openCodex() {
        guard !isBusy, let status, !status.recoveryRequired else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: status.installedApp))
    }

    private func perform(_ command: DictationPatchCommand) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await service.execute(command)
            status = response.status
            if command != .status {
                activityLog = Redactor.sanitize(response.log)
            }
            if !response.ok {
                errorMessage = Redactor.sanitize(response.error?.message ?? L10n.text("patch.error.protocol"))
            }
        } catch {
            // A failed status read must never leave a stale, actionable switch.
            status = nil
            errorMessage = Redactor.sanitize(error.localizedDescription)
        }
    }
}
