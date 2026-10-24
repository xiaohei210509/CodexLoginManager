import Darwin
import Foundation
import CryptoKit

enum DictationPatchTransaction {
    struct Record: Codable {
        let app: URL
        let stage: URL
        let previousMode: DictationPatchState
        let previousFingerprint: String?
        let candidateFingerprint: String?

        init(app: URL, stage: URL, previousMode: DictationPatchState,
             previousFingerprint: String? = nil, candidateFingerprint: String? = nil) {
            self.app = app
            self.stage = stage
            self.previousMode = previousMode
            self.previousFingerprint = previousFingerprint
            self.candidateFingerprint = candidateFingerprint
        }
    }

    static func replace(
        app: URL, source: URL, journal: URL, mode: DictationPatchState,
        previousMode: DictationPatchState,
        validate: (URL, DictationPatchState) async throws -> Void,
        stopped: () async throws -> Void,
        copy: (URL, URL) async throws -> Void,
        previousFingerprint: String? = nil, candidateFingerprint: String? = nil,
        afterOriginalMoved: () throws -> Void = {}
    ) async throws {
        let fm = FileManager.default
        try require(!fm.fileExists(atPath: journal.path), "patch.recovery_required")
        try require(app.resolvingSymlinksInPath().path == app.path && app.path != source.resolvingSymlinksInPath().path)
        try await stopped()
        try await validate(app, previousMode)
        try checkFingerprint(app, expected: previousFingerprint)
        try require(previousMode != .unknown || (previousFingerprint != nil && candidateFingerprint != nil))
        let stage = app.deletingLastPathComponent().appendingPathComponent(".codex-dictation-stage-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let candidate = stage.appendingPathComponent("candidate.app")
        let previous = stage.appendingPathComponent("previous.app")
        var moved = false
        do {
            try await copy(source, candidate)
            try await validate(candidate, mode)
            try checkFingerprint(candidate, expected: candidateFingerprint)
            try await stopped()
            try await validate(app, previousMode)
            try checkFingerprint(app, expected: previousFingerprint)
            try JSONEncoder().encode(Record(app: app, stage: stage, previousMode: previousMode,
                previousFingerprint: previousFingerprint, candidateFingerprint: candidateFingerprint))
                .write(to: journal, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
            try fm.moveItem(at: app, to: previous)
            moved = true
            try afterOriginalMoved()
            try fm.moveItem(at: candidate, to: app)
            try await validate(app, mode)
            try checkFingerprint(app, expected: candidateFingerprint)
            try fm.removeItem(at: journal)
        } catch {
            if moved {
                do {
                    if fm.fileExists(atPath: app.path) {
                        try fm.moveItem(at: app, to: stage.appendingPathComponent("failed.app"))
                    }
                    try fm.moveItem(at: previous, to: app)
                } catch {
                    // Preserve all copies and the journal if rollback itself fails.
                    throw DictationPatchError.executionFailed(L10n.text("patch.error.rollback"))
                }
            }
            if fm.fileExists(atPath: journal.path) { try fm.removeItem(at: journal) }
            try? fm.removeItem(at: stage)
            throw error
        }
        try? fm.removeItem(at: stage)
    }

    static func recover(
        app: URL, journal: URL,
        validate: (URL, DictationPatchState) async throws -> Void,
        stopped: () async throws -> Void
    ) async throws {
        try await stopped()
        let fm = FileManager.default
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: journal))
        try require(record.app.path == app.path && app.resolvingSymlinksInPath().path == app.path)
        try require(record.stage.deletingLastPathComponent().path == app.deletingLastPathComponent().path)
        try require(record.stage.lastPathComponent.hasPrefix(".codex-dictation-stage-"))
        try require(record.stage.resolvingSymlinksInPath().path == record.stage.path)
        try require(record.previousMode == .on || record.previousMode == .off ||
                    (record.previousMode == .unknown && record.previousFingerprint != nil && record.candidateFingerprint != nil))
        let previous = record.stage.appendingPathComponent("previous.app")
        if fm.fileExists(atPath: previous.path) {
            try await validate(previous, record.previousMode)
            try checkFingerprint(previous, expected: record.previousFingerprint)
            if fm.fileExists(atPath: app.path) {
                if let expected = record.candidateFingerprint {
                    try checkFingerprint(app, expected: expected)
                } else {
                    do { try await validate(app, .on) }
                    catch { try await validate(app, .off) }
                }
                try fm.moveItem(at: app, to: record.stage.appendingPathComponent("interrupted.app"))
            }
            try fm.moveItem(at: previous, to: app)
            try await validate(app, record.previousMode)
            try checkFingerprint(app, expected: record.previousFingerprint)
        } else {
            try await validate(app, record.previousMode)
            try checkFingerprint(app, expected: record.previousFingerprint)
        }
        try fm.removeItem(at: journal)
        try? fm.removeItem(at: record.stage)
    }

    private static func checkFingerprint(_ app: URL, expected: String?) throws {
        if let expected { try require(try fingerprint(app) == expected) }
    }

    static func fingerprint(_ app: URL) throws -> String {
        try require(app.resolvingSymlinksInPath().path == app.path)
        var hash = SHA256()
        func append(_ path: String, _ value: String) {
            hash.update(data: Data((path + "\0" + value + "\0").utf8))
        }
        func walk(_ directory: URL, relative: String, depth: Int) throws {
            try require(depth < 64)
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in children {
                let path = relative + url.lastPathComponent
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let type = attributes[.type] as? FileAttributeType
                let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                if type == .typeSymbolicLink {
                    append(path, "L" + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path)))
                } else if type == .typeRegular {
                    append(path, "F\(mode):" + (try DictationPatchRecipe.fileSHA(url)))
                } else if type == .typeDirectory {
                    append(path, "D\(mode)")
                    try walk(url, relative: path + "/", depth: depth + 1)
                } else { throw AdaptivePatchFailure.incompatible }
            }
        }
        try walk(app, relative: "", depth: 0)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class DictationPatchLock {
    private let descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try require(directory.resolvingSymlinksInPath().path == directory.path)
        let opened = Darwin.open(directory.appendingPathComponent("operation.lock").path,
                                 O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard opened >= 0 else { throw DictationPatchError.executionFailed(L10n.text("patch.error.lock")) }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            throw DictationPatchError.executionFailed(L10n.text("patch.error.lock"))
        }
        descriptor = opened
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
