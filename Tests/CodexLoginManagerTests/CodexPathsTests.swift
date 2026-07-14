import Foundation
import XCTest
@testable import CodexLoginManager

final class CodexPathsTests: XCTestCase {
    func testAbbreviatesTheHomeDirectoryForDisplay() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertEqual(
            CodexPaths.abbreviatingHomeDirectory(in: homePath + "/.codex/auth.json"),
            "~/.codex/auth.json"
        )
    }

    func testPreservesPathsOutsideTheHomeDirectory() {
        XCTAssertEqual(
            CodexPaths.abbreviatingHomeDirectory(
                in: "/Applications/ChatGPT.app/Contents/Resources/codex"
            ),
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
    }
}
