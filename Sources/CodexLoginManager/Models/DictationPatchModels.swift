import Foundation

enum DictationPatchState: String, Codable, Sendable {
    case on, off, unknown, missing
}

enum DictationPatchCommand: String, Sendable {
    case status, on, off, recover

    var title: String {
        L10n.text("patch.command.\(rawValue)")
    }
}

struct DictationPatchStatus: Codable, Equatable, Sendable {
    let state: DictationPatchState
    let installedApp: String
    let installedVersion: String?
    let supportedVersion: String
    let runningProcessCount: Int
    let recoveryRequired: Bool
    let officialBackupAvailable: Bool
    let patchedArtifactAvailable: Bool
    let installationWritable: Bool
    let checkedAt: String

    var isSupported: Bool { state == .on || state == .off }
    var isRunning: Bool { runningProcessCount > 0 }
    var canSwitch: Bool {
        isSupported && !isRunning && !recoveryRequired && officialBackupAvailable
            && patchedArtifactAvailable && installationWritable
    }
    var canRecover: Bool { recoveryRequired && !isRunning && installationWritable }
    var title: String { L10n.text("patch.state.\(state.rawValue)") }
}

struct DictationPatchResponse: Codable, Sendable {
    struct Failure: Codable, Sendable { let message: String }
    let schemaVersion: Int
    let ok: Bool
    let status: DictationPatchStatus?
    let log: String
    let error: Failure?

    static func decode(_ text: String) throws -> DictationPatchResponse {
        let response = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard response.schemaVersion == 1 else { throw DictationPatchError.unsupportedProtocol }
        return response
    }
}

enum DictationPatchError: LocalizedError {
    case missingTool, missingNode, unsupportedProtocol, executionFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingTool: L10n.text("patch.error.missing_tool")
        case .missingNode: L10n.text("patch.error.missing_node")
        case .unsupportedProtocol: L10n.text("patch.error.protocol")
        case let .executionFailed(message): message
        }
    }
}
