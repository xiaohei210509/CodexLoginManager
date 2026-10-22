import Foundation

struct DictationPatchService: Sendable {
    let toolDirectory: URL
    private let nodeOverride: String?
    private let runner: ProcessRunner

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Playground/codex-dictation-research", isDirectory: true)
    }

    init(toolDirectory: URL, nodePath: String? = nil, runner: ProcessRunner = ProcessRunner()) {
        self.toolDirectory = toolDirectory
        self.nodeOverride = nodePath
        self.runner = runner
    }

    func execute(_ command: DictationPatchCommand) async throws -> DictationPatchResponse {
        let script = toolDirectory.appendingPathComponent("dictation-patch.mjs")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw DictationPatchError.missingTool
        }
        guard let node = resolveNode() else { throw DictationPatchError.missingNode }
        let result = try await runner.run(
            executablePath: node,
            arguments: [script.path, "--json", command.rawValue],
            // A filesystem transaction must not be killed midway by a UI timer.
            timeoutSeconds: command == .status ? 45 : nil
        )
        guard let response = try? DictationPatchResponse.decode(result.stdout) else {
            throw DictationPatchError.executionFailed(
                Redactor.sanitize(result.combinedOutput.isEmpty
                    ? L10n.text("patch.error.protocol") : result.combinedOutput)
            )
        }
        if result.exitCode != 0 && response.ok {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.protocol"))
        }
        return response
    }

    private func resolveNode() -> String? {
        let manager = FileManager.default
        if let nodeOverride {
            return manager.isExecutableFile(atPath: nodeOverride) ? nodeOverride : nil
        }
        let home = manager.homeDirectoryForCurrentUser
        var candidates = [
            "/opt/homebrew/bin/node", "/usr/local/bin/node",
            "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node",
        ]
        let versions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let entries = try? manager.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil) {
            candidates += entries.sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appendingPathComponent("bin/node").path }
        }
        return candidates.first { manager.isExecutableFile(atPath: $0) }
    }
}
