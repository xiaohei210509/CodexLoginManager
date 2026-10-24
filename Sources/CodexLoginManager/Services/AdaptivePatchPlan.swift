import Foundation

struct AdaptivePatchPlan: Codable, Sendable {
    struct Slot: Codable, Sendable {
        let offset: UInt64
    }
    let schemaVersion: Int
    let version: String
    let build: String
    let originalArchiveSha256: String
    let patchedArchiveSha256: String
    let originalHeaderSha256: String
    let patchedHeaderSha256: String
    let originalFrameworkSha256: String
    let slots: [Slot]
    let originalDigest: String
    let patchedDigest: String
    let member: String

    var key: String { "\(DictationPatchRecipe.sha(Data(build.utf8)).prefix(12))-\(originalArchiveSha256)" }

    static func analyze(_ app: URL) throws -> (plan: Self, archive: Data) {
        let info = try Self.info(app)
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              var integrity = info["ElectronAsarIntegrity"] as? [String: [String: String]] else {
            throw AdaptivePatchFailure.incompatible
        }
        let original = try Data(contentsOf: app.appendingPathComponent("Contents/Resources/app.asar"))
        let archive = try AdaptivePatchArchive(original)
        let originalHeader = DictationPatchRecipe.sha(archive.headerBytes)
        try require(integrity["Resources/app.asar"]?["hash"] == originalHeader)
        let native = app.appendingPathComponent("Contents/Frameworks/Codex Framework.framework/Codex Framework")
        let nativeBytes = try Data(contentsOf: native, options: .mappedIfSafe)
        let originalDigest = digest(integrity)
        let slots = try nativeSlots(nativeBytes, expectedDigest: originalDigest)
        let result = try archive.patch()
        let patchedHeader = DictationPatchRecipe.sha(try AdaptivePatchArchive(result.archive).headerBytes)
        integrity["Resources/app.asar"]?["hash"] = patchedHeader
        return (Self(schemaVersion: 1, version: version, build: build,
                     originalArchiveSha256: DictationPatchRecipe.sha(original),
                     patchedArchiveSha256: DictationPatchRecipe.sha(result.archive),
                     originalHeaderSha256: originalHeader, patchedHeaderSha256: patchedHeader,
                     originalFrameworkSha256: try DictationPatchRecipe.fileSHA(native), slots: slots,
                     originalDigest: originalDigest, patchedDigest: digest(integrity), member: result.member),
                result.archive)
    }

    static func info(_ app: URL) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil
        ) as? [String: Any], result["CFBundleIdentifier"] as? String == "com.openai.codex" else {
            throw AdaptivePatchFailure.incompatible
        }
        return result
    }

    static func digest(_ dictionary: [String: [String: String]]) -> String {
        DictationPatchRecipe.sha(Data(dictionary.keys.sorted().map {
            $0 + (dictionary[$0]?["algorithm"] ?? "") + (dictionary[$0]?["hash"] ?? "")
        }.joined().utf8))
    }

    static func nativeSlots(_ data: Data, expectedDigest: String) throws -> [Slot] {
        var slices: [(Int, Int)] = []
        let magic = try data.integer32(at: 0, bigEndian: true)
        if magic == 0xcafebabe || magic == 0xcafebabf {
            let count = Int(try data.integer32(at: 4, bigEndian: true))
            try require(count > 0 && count <= 16)
            for i in 0..<count {
                let start = 8 + i * (magic == 0xcafebabe ? 20 : 32)
                let offset = magic == 0xcafebabe
                    ? UInt64(try data.integer32(at: start + 8, bigEndian: true))
                    : try data.integer64(at: start + 8, bigEndian: true)
                let size = magic == 0xcafebabe
                    ? UInt64(try data.integer32(at: start + 12, bigEndian: true))
                    : try data.integer64(at: start + 16, bigEndian: true)
                try require(offset <= UInt64(data.count) && size <= UInt64(data.count) - offset)
                slices.append((Int(offset), Int(size)))
            }
        } else { slices = [(0, data.count)] }
        var result: [Slot] = []
        for (base, size) in slices {
            try require(size >= 32 && (try data.integer32(at: base)) == 0xfeedfacf)
            let count = Int(try data.integer32(at: base + 16))
            let commandBytes = Int(try data.integer32(at: base + 20))
            try require(commandBytes <= size - 32 && count > 0 && count <= commandBytes / 8)
            let end = base + 32 + commandBytes
            var position = base + 32
            var found: [Slot] = []
            func name(_ offset: Int) -> String {
                String(decoding: data[offset..<(offset + 16)].prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            for _ in 0..<count {
                try require(position <= end - 8)
                let command = try data.integer32(at: position)
                let length = Int(try data.integer32(at: position + 4))
                try require(length >= 8 && length <= end - position)
                if command == 0x19 {
                    try require(length >= 72)
                    let sections = Int(try data.integer32(at: position + 64))
                    try require(sections <= (length - 72) / 80)
                    for j in 0..<sections {
                        let section = position + 72 + j * 80
                        if name(section) == "__asar_integrity" && name(section + 16) == "__DATA_CONST" {
                            let offset = Int(try data.integer32(at: section + 48))
                            try require(try data.integer64(at: section + 40) == 66 && offset <= size - 66)
                            let absolute = base + offset
                            try validateSlot(data.subdata(in: absolute..<(absolute + 66)), digest: expectedDigest)
                            found.append(Slot(offset: UInt64(absolute)))
                        }
                    }
                }
                position += length
            }
            try require(position == end && found.count == 1)
            result += found
        }
        try require(!result.isEmpty && Set(result.map(\.offset)).count == result.count)
        return result
    }

    static func validateSlot(_ data: Data, digest: String) throws {
        try require(data.count == 66)
        try require(String(data: data.prefix(32), encoding: .ascii) == "AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A")
        try require(Array(data[32..<34]) == [1, 1])
        try require(data.suffix(32).map { String(format: "%02x", $0) }.joined() == digest)
    }

    func verifySlots(_ url: URL, patched: Bool) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        for slot in slots {
            try handle.seek(toOffset: slot.offset)
            try Self.validateSlot(try handle.read(upToCount: 66) ?? Data(),
                                  digest: patched ? patchedDigest : originalDigest)
        }
    }
}
