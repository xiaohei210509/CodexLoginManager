import AppKit
import Foundation

@MainActor
final class DictationPatchViewModel: ObservableObject {
    @Published private(set) var status: DictationPatchStatus?
    @Published private(set) var isBusy = false
    @Published private(set) var activityLog = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var toolDirectory: URL
    @Published var pendingCommand: DictationPatchCommand?
    @Published var choosingDirectory = false

    private let defaults: UserDefaults
    private static let directoryKey = "dictationPatchToolDirectory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.toolDirectory = defaults.string(forKey: Self.directoryKey)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? DictationPatchService.defaultDirectory
    }

    var canSwitch: Bool { status?.canSwitch == true && !isBusy }
    var canRecover: Bool { status?.canRecover == true && !isBusy }

    func refresh() async {
        guard !isBusy else { return }
        await perform(.status)
    }

    func selectToolDirectory(_ url: URL) async {
        guard !isBusy else { return }
        toolDirectory = url
        defaults.set(url.path, forKey: Self.directoryKey)
        status = nil
        await refresh()
    }

    func confirmCommand(_ command: DictationPatchCommand) async {
        pendingCommand = nil
        guard command == .recover ? canRecover : canSwitch else { return }
        await perform(command)
    }

    func showToolDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: toolDirectory.path)
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
            let response = try await DictationPatchService(toolDirectory: toolDirectory).execute(command)
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
