import Foundation

struct CodexUpdate: Equatable, Sendable {
    let version: String
    let build: String
    let minimumSystemVersion: String
    let architecture: String
    let url: URL
    let length: Int64
    let signature: Data

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }

    static func numbers(_ value: String) -> [UInt64]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 8 else { return nil }
        let numbers = parts.compactMap { part -> UInt64? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return UInt64(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        guard let left = numbers(a), let right = numbers(b) else { return nil }
        for i in 0..<max(left.count, right.count) {
            let x = i < left.count ? left[i] : 0
            let y = i < right.count ? right[i] : 0
            if x != y { return x > y ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    func isNewer(version: String, build: String) -> Bool {
        Self.compare(self.build, build) == .orderedDescending &&
            [ComparisonResult.orderedSame, .orderedDescending].contains(Self.compare(self.version, version))
    }

    static func allowedURL(_ url: URL, feed: Bool = false) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { return false }
        if feed && url.host == "updates.oaistatic.com" && url.path == "/codex/app/appcast" { return true }
        guard url.host == "persistent.oaistatic.com", url.path.hasPrefix("/codex-app-prod/"),
              !url.pathComponents.contains("..") else { return false }
        return feed ? url.lastPathComponent.hasPrefix("appcast-") && url.pathExtension == "xml"
            : url.pathExtension == "zip"
    }
}

enum CodexUpdateFailure: LocalizedError {
    case invalidFeed, invalidDownload, invalidSignature, wrongVersion, quitFailed, changedInstallation
    var errorDescription: String? { L10n.text("update.error.\(self)") }
}

final class CodexAppcastParser: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var fields: [String: String] = [:]
    private var enclosure: [String: String]?
    private var items: [CodexUpdate] = []
    private var invalid = false
    private var sawChannel = false

    static func parse(_ data: Data, architecture: String, systemVersion: String) throws -> [CodexUpdate] {
        guard data.count <= 2_000_000, !data.isEmpty,
              let text = String(data: data, encoding: .utf8), !text.contains("<!DOCTYPE"),
              !text.contains("<!ENTITY") else { throw CodexUpdateFailure.invalidFeed }
        let delegate = CodexAppcastParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, delegate.sawChannel else { throw CodexUpdateFailure.invalidFeed }
        return delegate.items.filter {
            $0.architecture == architecture &&
                CodexUpdate.compare(systemVersion, $0.minimumSystemVersion) != nil &&
                CodexUpdate.compare(systemVersion, $0.minimumSystemVersion) != .orderedAscending
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if path.count > 32 { invalid = true; parser.abortParsing(); return }
        path.append(name)
        if path.count == 1 && name != "rss" { invalid = true; parser.abortParsing(); return }
        if path == ["rss", "channel"] { sawChannel = true }
        if name == "item" && path != ["rss", "channel", "item"] {
            invalid = true; parser.abortParsing(); return
        }
        if name == "item" { fields = [:]; enclosure = nil }
        if path.suffix(2) == ["item", "enclosure"] {
            if enclosure != nil || attributes["sparkle:deltaFrom"] != nil { invalid = true }
            enclosure = attributes
        }
    }

    func parser(_ parser: XMLParser, foundCharacters text: String) {
        guard path.count >= 2, path[path.count - 2] == "item", let name = path.last else { return }
        fields[name, default: ""] += text
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !path.isEmpty { path.removeLast() } }
        guard name == "item" else { return }
        func field(_ name: String) -> String { fields["sparkle:" + name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let enclosure, let rawURL = enclosure["url"], let url = URL(string: rawURL),
              CodexUpdate.allowedURL(url), let length = Int64(enclosure["length"] ?? ""),
              length > 0, length <= 3_000_000_000,
              let signature = Data(base64Encoded: enclosure["sparkle:edSignature"] ?? ""), signature.count == 64,
              CodexUpdate.numbers(field("version")) != nil,
              CodexUpdate.numbers(field("shortVersionString")) != nil,
              CodexUpdate.numbers(field("minimumSystemVersion")) != nil else {
            invalid = true
            return
        }
        items.append(CodexUpdate(version: field("shortVersionString"), build: field("version"),
            minimumSystemVersion: field("minimumSystemVersion"), architecture: field("hardwareRequirements"),
            url: url, length: length, signature: signature))
    }
}
