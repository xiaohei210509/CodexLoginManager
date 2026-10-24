import Foundation
import JavaScriptCore

enum AdaptivePatchFailure: LocalizedError {
    case incompatible, notNeeded
    var errorDescription: String? {
        L10n.text(self == .notNeeded ? "patch.not_needed" : "patch.unsupported")
    }
}

struct DictationSourceLocator {
    struct Match {
        let range: Range<Int>
        let enabled: Bool
    }

    func matches(_ source: String) throws -> [Match] {
        guard let context = JSContext(),
              let parserURL = Bundle.module.url(forResource: "acorn", withExtension: "js"),
              let locatorURL = Bundle.module.url(forResource: "dictation-locator", withExtension: "js") else {
            throw DictationPatchError.executionFailed(L10n.text("patch.error.recipe"))
        }
        context.evaluateScript(try String(contentsOf: parserURL, encoding: .utf8))
        context.evaluateScript(try String(contentsOf: locatorURL, encoding: .utf8))
        let result = context.objectForKeyedSubscript("locateDictation")?.call(withArguments: [source])
        guard context.exception == nil, let array = result?.toArray() as? [[String: Any]] else {
            throw AdaptivePatchFailure.incompatible
        }
        return try array.map {
            guard let start = $0["start"] as? Int, let end = $0["end"] as? Int,
                  let enabled = $0["enabled"] as? Bool, end >= start,
                  let range = Range(NSRange(location: start, length: end - start), in: source) else {
                throw AdaptivePatchFailure.incompatible
            }
            let lower = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            let upper = source.utf8.distance(from: source.utf8.startIndex, to: range.upperBound)
            return Match(range: lower..<upper, enabled: enabled)
        }
    }
}

struct AdaptivePatchArchive {
    let bytes: Data
    let headerBytes: Data
    let header: [String: Any]
    let dataOffset: Int

    init(_ data: Data) throws {
        try require(data.count >= 16)
        let length = Int(try data.integer32(at: 12))
        let offset = Int(try data.integer32(at: 4)) + 8
        try require(length > 0 && length <= data.count - 16 && offset >= length + 16 && offset <= data.count)
        let json = data.subdata(in: 16..<(16 + length))
        guard let dictionary = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              dictionary["files"] is [String: Any] else { throw AdaptivePatchFailure.incompatible }
        bytes = data
        headerBytes = json
        header = dictionary
        dataOffset = offset
    }

    struct Member {
        let path: [String]
        let entry: [String: Any]
        let range: Range<Int>
    }

    func members() throws -> [Member] {
        var result: [Member] = []
        func walk(_ dictionary: [String: Any], _ prefix: [String], _ depth: Int) throws {
            try require(depth < 64)
            guard let files = dictionary["files"] as? [String: [String: Any]] else {
                throw AdaptivePatchFailure.incompatible
            }
            for (name, entry) in files {
                try require(!name.isEmpty && ![".", ".."].contains(name) && !name.contains("/"))
                if entry["files"] != nil { try walk(entry, prefix + [name], depth + 1) }
                else if entry["unpacked"] as? Bool != true && entry["link"] == nil {
                    guard let text = entry["offset"] as? String, let offset = Int(text),
                          let size = entry["size"] as? Int else { throw AdaptivePatchFailure.incompatible }
                    try require(offset >= 0 && offset <= bytes.count - dataOffset && size >= 0)
                    let start = dataOffset + offset
                    try require(size <= bytes.count - start)
                    result.append(Member(path: prefix + [name], entry: entry, range: start..<(start + size)))
                }
            }
        }
        try walk(header, [], 0)
        return result
    }

    func patch() throws -> (archive: Data, member: String) {
        var candidates: [(Member, DictationSourceLocator.Match)] = []
        for member in try members() where member.path.first == "webview" && member.path.last?.hasSuffix(".js") == true {
            let data = bytes.subdata(in: member.range)
            guard data.range(of: Data("workspace-dictation".utf8)) != nil,
                  data.range(of: Data("requiresFirstPartyInference".utf8)) != nil,
                  let source = String(data: data, encoding: .utf8) else { continue }
            for match in try DictationSourceLocator().matches(source) { candidates.append((member, match)) }
        }
        guard candidates.count == 1 else { throw AdaptivePatchFailure.incompatible }
        let (member, match) = candidates[0]
        guard match.enabled else { throw AdaptivePatchFailure.notNeeded }
        guard var integrity = member.entry["integrity"] as? [String: Any],
              integrity["algorithm"] as? String == "SHA256",
              let hash = integrity["hash"] as? String,
              let blockSize = integrity["blockSize"] as? Int,
              let blocks = integrity["blocks"] as? [String], blockSize > 0 else {
            throw AdaptivePatchFailure.incompatible
        }
        var memberBytes = bytes.subdata(in: member.range)
        try require(DictationPatchRecipe.sha(memberBytes) == hash && match.range.count >= 2)
        let oldBlocks = stride(from: 0, to: memberBytes.count, by: blockSize).map {
            DictationPatchRecipe.sha(memberBytes.subdata(in: $0..<min($0 + blockSize, memberBytes.count)))
        }
        try require(oldBlocks == blocks)
        let replacement = Data(("!1" + String(repeating: " ", count: match.range.count - 2)).utf8)
        memberBytes.replaceSubrange(match.range, with: replacement)
        integrity["hash"] = DictationPatchRecipe.sha(memberBytes)
        integrity["blocks"] = stride(from: 0, to: memberBytes.count, by: blockSize).map {
            DictationPatchRecipe.sha(memberBytes.subdata(in: $0..<min($0 + blockSize, memberBytes.count)))
        }
        var updatedEntry = member.entry
        updatedEntry["integrity"] = integrity
        func replacing(_ node: [String: Any], path: ArraySlice<String>) throws -> [String: Any] {
            guard let name = path.first, var files = node["files"] as? [String: [String: Any]],
                  let child = files[name] else { throw AdaptivePatchFailure.incompatible }
            files[name] = path.count == 1 ? updatedEntry : try replacing(child, path: path.dropFirst())
            var result = node
            result["files"] = files
            return result
        }
        let changed = try replacing(header, path: member.path[...])
        let json = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])
        let padding = (4 - json.count % 4) % 4
        try require(json.count < Int(UInt32.max) - 16)
        var result = Data()
        for value in [4, 8 + json.count + padding, 4 + json.count + padding, json.count] {
            result.appendLittleEndian(UInt32(value))
        }
        result.append(json)
        result.append(Data(repeating: 0, count: padding))
        var payload = bytes.subdata(in: dataOffset..<bytes.count)
        let offset = member.range.lowerBound - dataOffset
        payload.replaceSubrange(offset..<(offset + memberBytes.count), with: memberBytes)
        result.append(payload)
        _ = try AdaptivePatchArchive(result).members()
        return (result, member.path.joined(separator: "/"))
    }
}

extension Data {
    func integer32(at offset: Int, bigEndian: Bool = false) throws -> UInt32 {
        try require(offset >= 0 && offset <= count - 4)
        return (0..<4).reduce(UInt32(0)) {
            $0 | UInt32(self[offset + $1]) << (UInt32(bigEndian ? 3 - $1 : $1) * 8)
        }
    }

    func integer64(at offset: Int, bigEndian: Bool = false) throws -> UInt64 {
        try require(offset >= 0 && offset <= count - 8)
        return (0..<8).reduce(UInt64(0)) {
            $0 | UInt64(self[offset + $1]) << (UInt64(bigEndian ? 7 - $1 : $1) * 8)
        }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        for shift in [0, 8, 16, 24] { append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
}
