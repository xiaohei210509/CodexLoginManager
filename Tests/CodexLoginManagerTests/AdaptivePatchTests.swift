import XCTest
@testable import CodexLoginManager

final class AdaptivePatchTests: XCTestCase {
    func testASTLocatorHandlesMinificationQuotesAndUnicodeWithoutExecutingCode() throws {
        for source in [
            #"globalThis.danger();const a={dictation:{accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0}};"#,
            #"const 名字="听写";const b={dictation:{'requiresFirstPartyInference':true,accessPolicy:`workspace-dictation`}};"#
        ] {
            let matches = try DictationSourceLocator().matches(source)
            XCTAssertEqual(matches.count, 1)
            XCTAssertTrue(try XCTUnwrap(matches.first).enabled)
            let range = try XCTUnwrap(matches.first).range
            XCTAssertTrue(["!0", "true"].contains(String(decoding: Array(source.utf8)[range], as: UTF8.self)))
        }
    }

    func testASTLocatorRejectsDynamicSpreadAndDuplicateFlags() {
        for properties in [
            #"accessPolicy:"workspace-dictation",requiresFirstPartyInference:getFlag()"#,
            #"accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0,...other"#,
            #"accessPolicy:"other",accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0"#,
            #"accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0,requiresFirstPartyInference:!0"#
        ] {
            XCTAssertThrowsError(try DictationSourceLocator().matches("const a={dictation:{\(properties)}}"))
        }
    }

    func testTokenizerDoesNotMatchCommentsStringsRegexOrComputedKeys() throws {
        let source = #"""
        const text='dictation:{accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0}';
        const regex=/dictation:\{requiresFirstPartyInference:!0\}/;
        // dictation:{accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0}
        const computed={["dictation"]:{accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0}};
        const actual={dictation:{accessPolicy:"workspace-dictation",requiresFirstPartyInference:!0}};
        """#
        XCTAssertEqual(try DictationSourceLocator().matches(source).count, 1)
    }

    private func archive(source: String, name: String = "random-hash.js") throws -> Data {
        let bytes = Data(source.utf8)
        let integrity: [String: Any] = ["algorithm": "SHA256", "hash": DictationPatchRecipe.sha(bytes),
            "blockSize": 16, "blocks": stride(from: 0, to: bytes.count, by: 16).map {
                DictationPatchRecipe.sha(bytes.subdata(in: $0..<min($0 + 16, bytes.count)))
            }]
        let header: [String: Any] = ["files": ["webview": ["files": [name: [
            "offset": "0", "size": bytes.count, "integrity": integrity
        ]]]]]
        let json = try JSONSerialization.data(withJSONObject: header)
        let padding = (4 - json.count % 4) % 4
        var result = Data()
        for value in [4, 8 + json.count + padding, 4 + json.count + padding, json.count] {
            result.appendLittleEndian(UInt32(value))
        }
        result += json + Data(repeating: 0, count: padding) + bytes
        return result
    }

    func testArchiveAdaptsWithoutFilenameOrVersionPinAndUpdatesAllHashes() throws {
        let source = #"const a={dictation:{requiresFirstPartyInference:true,accessPolicy:"workspace-dictation"}};"#
        let original = try archive(source: source)
        let result = try AdaptivePatchArchive(original).patch()
        let patched = try AdaptivePatchArchive(result.archive)
        let member = try XCTUnwrap(patched.members().first)
        XCTAssertEqual(member.range.count, source.utf8.count)
        XCTAssertEqual(result.member, "webview/random-hash.js")
        let bytes = result.archive.subdata(in: member.range)
        let match = try XCTUnwrap(DictationSourceLocator().matches(String(decoding: bytes, as: UTF8.self)).first)
        XCTAssertFalse(match.enabled)
        let integrity = try XCTUnwrap(member.entry["integrity"] as? [String: Any])
        XCTAssertEqual(integrity["hash"] as? String, DictationPatchRecipe.sha(bytes))
        XCTAssertEqual(integrity["blocks"] as? [String], stride(from: 0, to: bytes.count, by: 16).map {
            DictationPatchRecipe.sha(bytes.subdata(in: $0..<min($0 + 16, bytes.count)))
        })
        XCTAssertThrowsError(try patched.patch()) { XCTAssertEqual($0 as? AdaptivePatchFailure, .notNeeded) }
    }

    func testArchiveRefusesAmbiguityCorruptMemberAndInvalidBounds() throws {
        let object = #"dictation:{requiresFirstPartyInference:!0,accessPolicy:"workspace-dictation"}"#
        XCTAssertThrowsError(try AdaptivePatchArchive(archive(source: "const a={\(object)},b={\(object)};")).patch())
        var corrupt = try archive(source: "const a={\(object)};")
        corrupt[corrupt.count - 1] ^= 1
        XCTAssertThrowsError(try AdaptivePatchArchive(corrupt).patch())
        XCTAssertThrowsError(try AdaptivePatchArchive(Data(repeating: 255, count: 16)))
        XCTAssertThrowsError(try AdaptivePatchPlan.nativeSlots(Data(repeating: 0, count: 64), expectedDigest: ""))
    }

    func testCacheDoesNotConfuseBuildsWithTheSameArchive() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let bytes = Data("same archive across two native builds".utf8)
        try bytes.write(to: app.appendingPathComponent("Contents/Resources/app.asar"))
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.openai.codex", "CFBundleShortVersionString": "26.2", "CFBundleVersion": "2"
        ], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let service = DictationPatchService(installedApp: app, storageDirectory: root.appendingPathComponent("storage"))
        func record(_ version: String, _ build: String) throws {
            let plan = AdaptivePatchPlan(schemaVersion: 1, version: version, build: build,
                originalArchiveSha256: DictationPatchRecipe.sha(bytes), patchedArchiveSha256: "unused",
                originalHeaderSha256: "unused", patchedHeaderSha256: "unused",
                originalFrameworkSha256: "unused", slots: [], originalDigest: "unused",
                patchedDigest: "unused", member: "webview/example.js")
            let directory = service.directory(plan)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(plan).write(to: directory.appendingPathComponent("plan.json"))
        }
        try record("26.1", "1")
        XCTAssertNil(try service.storedPlan(app))
        try record("26.2", "2")
        XCTAssertEqual(try service.storedPlan(app)?.version, "26.2")
        XCTAssertEqual(try service.storedPlan(app)?.build, "2")
    }
}
