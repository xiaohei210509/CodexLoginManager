import XCTest
@testable import CodexLoginManager

final class RedactorTests: XCTestCase {
    func testSanitizesNamedSecrets() {
        let input = [
            "access_" + "token = \"example-access-value\"",
            "refresh_" + "token: example-refresh-value",
            "OPENAI_" + "API_KEY=example-api-value"
        ].joined(separator: "\n")

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains("example-access-value"))
        XCTAssertFalse(sanitized.contains("example-refresh-value"))
        XCTAssertFalse(sanitized.contains("example-api-value"))
        XCTAssertTrue(sanitized.contains("[redacted]"))
    }

    func testSanitizesStandaloneAPIKeyAndJWT() {
        let apiKey = "sk-" + String(repeating: "a", count: 32)
        let jwt = ["eyJheader", "payload", "signature"].joined(separator: ".")

        let sanitized = Redactor.sanitize("\(apiKey)\n\(jwt)")

        XCTAssertEqual(sanitized, "[redacted-api-key]\n[redacted-jwt]")
    }

    func testPreservesOrdinaryStatusText() {
        XCTAssertEqual(
            Redactor.sanitize("Logged in using ChatGPT"),
            "Logged in using ChatGPT"
        )
    }

    func testUsesPlaceholderForBlankOutput() {
        XCTAssertEqual(Redactor.sanitize(" \n\t"), L10n.text("redactor.no_output"))
    }
}
