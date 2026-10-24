import CryptoKit
import Foundation

struct DictationPatchRecipe: Decodable, Sendable {
    let version: String
    let memberPath: String
    let originalArchiveSha256: String
    let patchedArchiveSha256: String
    let originalHeaderSha256: String
    let patchedHeaderSha256: String
    let before: String
    let after: String
    let originalFrameworkSha256: String
    let patchedUnsignedFrameworkSha256: String
    let slotOffset: UInt64
    let originalDigest: String
    let patchedDigest: String

    static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "dictation-recipe", withExtension: "json") else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.recipe"))
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileSHA(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty {
            digest.update(data: block)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Keep the researched ASAR layout byte-for-byte; only the member and its
    // fixed-length integrity hashes change. Final hashes pin the entire output.
    func patchArchive(_ original: Data) throws -> Data {
        try require(Self.sha(original) == originalArchiveSha256)
        func uint32(_ offset: Int) throws -> Int {
            try require(offset >= 0 && offset + 4 <= original.count)
            return (0..<4).reduce(0) { $0 | (Int(original[offset + $1]) << ($1 * 8)) }
        }
        let headerLength = try uint32(12)
        let dataOffset = try uint32(4) + 8
        try require(headerLength > 0 && headerLength <= original.count - 16)
        try require(dataOffset >= 16 + headerLength && dataOffset <= original.count)
        let headerData = original.subdata(in: 16..<(16 + headerLength))
        try require(Self.sha(headerData) == originalHeaderSha256)
        guard var entry = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              var header = String(data: headerData, encoding: .utf8) else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
        }
        for component in memberPath.split(separator: "/") {
            guard let files = entry["files"] as? [String: Any],
                  let next = files[String(component)] as? [String: Any] else {
                throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
            }
            entry = next
        }
        guard let offsetText = entry["offset"] as? String, let offset = Int(offsetText),
              let size = entry["size"] as? Int, let integrity = entry["integrity"] as? [String: Any],
              let oldHash = integrity["hash"] as? String,
              let oldBlocks = integrity["blocks"] as? [String],
              let blockSize = integrity["blockSize"] as? Int else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
        }
        try require(offset >= 0 && offset <= original.count - dataOffset && size > 0)
        let start = dataOffset + offset
        try require(size <= original.count - start && blockSize > 0 && integrity["algorithm"] as? String == "SHA256")
        let member = original.subdata(in: start..<(start + size))
        try require(Self.sha(member) == oldHash)
        let anchor = Data(before.utf8)
        guard let range = member.range(of: anchor) else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.integrity"))
        }
        try require(member.range(of: anchor, in: range.upperBound..<member.count) == nil)
        var patchedMember = member
        patchedMember.replaceSubrange(range, with: Data(after.utf8))
        try require(patchedMember.count == member.count)
        let newBlocks = stride(from: 0, to: size, by: blockSize).map {
            Self.sha(patchedMember.subdata(in: $0..<min($0 + blockSize, size)))
        }
        try require(oldBlocks.count == newBlocks.count)
        var replacements = [oldHash: Self.sha(patchedMember)]
        for (old, new) in zip(oldBlocks, newBlocks) {
            if let existing = replacements[old] { try require(existing == new) }
            replacements[old] = new
        }
        for (old, new) in replacements { header = header.replacingOccurrences(of: old, with: new) }
        let patchedHeader = Data(header.utf8)
        try require(patchedHeader.count == headerLength && Self.sha(patchedHeader) == patchedHeaderSha256)
        var result = original
        result.replaceSubrange(start..<(start + size), with: patchedMember)
        result.replaceSubrange(16..<(16 + headerLength), with: patchedHeader)
        try require(Self.sha(result) == patchedArchiveSha256)
        return result
    }

    func frameworkSlot(_ url: URL, digest: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: slotOffset)
        let slot = try handle.read(upToCount: 66) ?? Data()
        try require(slot.count == 66)
        try require(String(data: slot.prefix(32), encoding: .ascii) == "AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A")
        try require(Array(slot[32..<34]) == [1, 1])
        try require(slot.suffix(32).map { String(format: "%02x", $0) }.joined() == digest)
    }
}

func require(_ condition: Bool, _ key: String = "patch.error.integrity",
             file: StaticString = #fileID, line: UInt = #line) throws {
    guard condition else {
        let context = key == "patch.error.integrity" ? " [\(file):\(line)]" : ""
        throw DictationPatchError.executionFailed(L10n.text(key) + context)
    }
}
