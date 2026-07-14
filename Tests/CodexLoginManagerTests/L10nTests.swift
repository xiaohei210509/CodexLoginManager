import XCTest
@testable import CodexLoginManager

final class L10nTests: XCTestCase {
    func testUsesSimplifiedChineseForRegionalChinesePreference() {
        XCTAssertEqual(
            L10n.text("header.title", preferredLanguages: ["zh-Hans-CN"]),
            "Codex 登录管理"
        )
    }

    func testUsesEnglishForEnglishPreference() {
        XCTAssertEqual(
            L10n.text("header.title", preferredLanguages: ["en-US"]),
            "Codex Login Manager"
        )
    }
}
