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

    func testSanitizesMultipleNamedSecretsOnOneLine() {
        let accessKey = "access_" + "token"
        let refreshKey = "refresh_" + "token"
        let firstSecret = "FIRST_" + "SECRET"
        let secondSecret = "SECOND_" + "SECRET"

        XCTAssertEqual(
            Redactor.sanitize(
                "\(accessKey)=\(firstSecret) \(refreshKey)=\(secondSecret)"
            ),
            "\(accessKey)=[redacted] \(refreshKey)=[redacted]"
        )
    }

    func testSanitizesQuotedJSONFieldsAndPreservesSiblingFields() {
        let accessKey = "access_" + "token"
        let secret = "opaque-json-value-" + String(repeating: "a", count: 20)
        let input = "{\"\(accessKey)\":\"\(secret)\",\"expires_at\":123,\"status\":\"ok\"}"

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertTrue(sanitized.contains("\"\(accessKey)\":\"[redacted]\""))
        XCTAssertTrue(sanitized.contains("\"expires_at\":123"))
        XCTAssertTrue(sanitized.contains("\"status\":\"ok\""))
    }

    func testSanitizesSingleQuotedAndCamelCaseAssignments() {
        let refreshKey = "refresh" + "Token"
        let apiKeyName = "openai" + "ApiKey"
        let refreshSecret = "opaque-refresh-" + String(repeating: "b", count: 20)
        let apiSecret = "opaque-api-" + String(repeating: "c", count: 20)
        let input = "'\(refreshKey)' = '\(refreshSecret)'\n\(apiKeyName)=\(apiSecret)"

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(refreshSecret))
        XCTAssertFalse(sanitized.contains(apiSecret))
        XCTAssertTrue(sanitized.contains("'\(refreshKey)' = '[redacted]'"))
    }

    func testSanitizesAuthorizationHeadersAndBearerTokenFields() {
        let authorizationSecret = "opaque-authorization-" + String(repeating: "d", count: 24)
        let proxySecret = "opaque-proxy-" + String(repeating: "e", count: 24)
        let bearerSecret = "opaque-bearer-" + String(repeating: "f", count: 24)
        let clientSecret = "opaque-client-" + String(repeating: "g", count: 24)
        let input = """
        Authorization: Bearer \(authorizationSecret)
        Proxy-Authorization: Basic \(proxySecret)
        bearerToken=\(bearerSecret)
        clientSecret=\(clientSecret)
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(authorizationSecret))
        XCTAssertFalse(sanitized.contains(proxySecret))
        XCTAssertFalse(sanitized.contains(bearerSecret))
        XCTAssertFalse(sanitized.contains(clientSecret))
    }

    func testSanitizesCommaSeparatedAuthorizationSchemes() {
        let digestSecret = "digest-response-" + String(repeating: "h", count: 24)
        let signatureSecret = "signature-value-" + String(repeating: "i", count: 24)
        let markerSuffixSecret = "marker-suffix-" + String(repeating: "j", count: 24)
        let input = """
        Authorization: Digest username="user", realm="example", response="\(digestSecret)"
        Authorization: AWS4-HMAC-SHA256 Credential=example, SignedHeaders=host, Signature=\(signatureSecret)
        Authorization: [redacted], response=\(markerSuffixSecret)
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(digestSecret))
        XCTAssertFalse(sanitized.contains(signatureSecret))
        XCTAssertFalse(sanitized.contains(markerSuffixSecret))
        XCTAssertEqual(
            sanitized,
            "Authorization: [redacted]\nAuthorization: [redacted]\nAuthorization: [redacted]"
        )
    }

    func testSanitizesEscapedJSONLogFieldsAndPreservesSiblingFields() {
        let accessKey = "access_" + "token"
        let secret = "escaped-json-secret-" + String(repeating: "g", count: 24)
        let input = #"payload={\"\#(accessKey)\":\"\#(secret)\",\"status\":\"ok\"}"#

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertTrue(sanitized.contains(#"\"access_token\":\"[redacted]\""#))
        XCTAssertTrue(sanitized.contains(#"\"status\":\"ok\""#))
    }

    func testSanitizesPrefixedMultilineEscapedJSONWithSiblingField() {
        let accessKey = "access_" + "token"
        let firstFragment = "prefixedOpaqueFragment"
        let finalFragment = "tailFragment"
        let input = #"""
        payload={\"\#(accessKey)\":
          \"\#(firstFragment)\"
          \"\#(finalFragment)\", \"status\":\"ok\"
        }
        """#

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(finalFragment))
        XCTAssertTrue(sanitized.contains(#"\"status\":\"ok\""#))
    }

    func testSanitizesQuotedValueWhoseClosingLineHasSiblingField() {
        let accessKey = "access_" + "token"
        let firstFragment = "firstSecretFragment123"
        let secondFragment = "secondSecretFragment456"
        let input = """
        "\(accessKey)": "\(firstFragment)
          \(secondFragment)", "status": "ok"
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("\"status\": \"ok\""))
    }

    func testSanitizesDoubleEscapedJSONLogFields() {
        let accessKey = "access_" + "token"
        let secret = "double-escaped-secret-" + String(repeating: "k", count: 24)
        let escapedQuote = String(repeating: "\\", count: 2) + "\""
        let input = "payload={\(escapedQuote)\(accessKey)\(escapedQuote):" +
            "\(escapedQuote)\(secret)\(escapedQuote)}"

        XCTAssertFalse(Redactor.sanitize(input).contains(secret))
    }

    func testSanitizesUnquotedSymbolsAndBearerValues() {
        let accessKey = "access_" + "token"
        let refreshKey = "refresh_" + "token"
        let symbolSecret = "abc$VERY-SECRET:value"
        let bearerSecret = "opaque-bearer-" + String(repeating: "g", count: 24)
        let input = """
        \(accessKey)=\(symbolSecret); status=failed
        \(refreshKey)=Bearer \(bearerSecret)
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(symbolSecret))
        XCTAssertFalse(sanitized.contains(bearerSecret))
        XCTAssertTrue(sanitized.contains("[redacted]"))
    }

    func testSanitizesVisibleASCIIInNamedSecrets() {
        let accessKey = "access_" + "token"
        let refreshKey = "refresh_" + "token"
        let clientKey = "client_" + "secret"
        let bracketSecret = "abc]synthetic-secret"
        let ampersandSecret = "abc&synthetic-secret"
        let dollarSecret = "abc$synthetic-secret"
        let percentSecret = "abc%synthetic-secret"
        let input = """
        \(accessKey)=\(bracketSecret)
        \(refreshKey)=\(ampersandSecret)
        \(clientKey):
          \(dollarSecret)
          \(percentSecret)
        status: complete
        """

        let sanitized = Redactor.sanitize(input)

        for secret in [bracketSecret, ampersandSecret, dollarSecret, percentSecret] {
            XCTAssertFalse(sanitized.contains(secret), sanitized)
        }
        XCTAssertTrue(sanitized.contains("status: complete"))
    }

    func testSanitizesSpacedAndPrefixedTokenFieldNames() {
        let secrets = (1...4).map { "named-field-secret-\($0)-" + String(repeating: "m", count: 16) }
        let input = """
        Access token: \(secrets[0])
        Refresh token: \(secrets[1])
        X-Access-Token: \(secrets[2])
        oauth_token=\(secrets[3])
        """

        let sanitized = Redactor.sanitize(input)

        for secret in secrets {
            XCTAssertFalse(sanitized.contains(secret), sanitized)
        }
    }

    func testSanitizesNamedSecretAcrossIndentedLines() {
        let refreshKey = "refresh_" + "token"
        let firstFragment = "abcDEF0123456789"
        let secondFragment = "_moreTOKEN987654"
        let input = """
        "\(refreshKey)":
          \(firstFragment)
          \(secondFragment)
        status: retry required
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("status: retry required"))
    }

    func testSanitizesNamedSecretInYAMLList() {
        let accessKey = "access_" + "token"
        let secret = "yaml-list-secret-" + String(repeating: "h", count: 24)
        let input = """
        - \(accessKey):
            \(secret)
        status: retry required
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertTrue(sanitized.contains("status: retry required"))
    }

    func testSanitizesNamedSecretBeyondFourWrappedLines() {
        let accessKey = "access_" + "token"
        let fragments = (1...6).map { "fragment\($0)" + String(repeating: "x", count: 12) }
        let input = (["\(accessKey):"] + fragments.map { "  \($0)" } + ["status: complete"])
            .joined(separator: "\n")

        let sanitized = Redactor.sanitize(input)

        for fragment in fragments {
            XCTAssertFalse(sanitized.contains(fragment))
        }
        XCTAssertTrue(sanitized.contains("status: complete"))
    }

    func testSanitizesSplitAPIKeyWithoutConsumingFollowingDiagnostic() {
        let firstFragment = "sk-" + "proj-a1a1a1a1a1a1"
        let secondFragment = "b2b2b2b2b2b2b2b2b2b2b2b2"
        let input = """
        credential: \(firstFragment)
            \(secondFragment)
        warning: request failed
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("[redacted-api-key]"))
        XCTAssertTrue(sanitized.contains("warning: request failed"))
    }

    func testSanitizesJWTSplitAtSegmentBoundaries() {
        let header = "eyJhbGciOiJIUzI1NiJ9."
        let payload = "eyJzdWIiOiIxMjM0NTY3ODkwIn0."
        let signature = "c2lnbmF0dXJlMTIz"
        let input = """
        \(header)
            \(payload)
            \(signature)
        error: unauthorized
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(header))
        XCTAssertFalse(sanitized.contains(payload))
        XCTAssertFalse(sanitized.contains(signature))
        XCTAssertTrue(sanitized.contains("[redacted-jwt]"))
        XCTAssertTrue(sanitized.contains("error: unauthorized"))
    }

    func testSanitizesJWTWhoseSegmentIsSplitAcrossLines() {
        let headerStart = "eyJhbGciOiJI"
        let remainder = "UzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0."
        let signature = "c2lnbmF0dXJlMTIz"
        let input = """
        \(headerStart)
            \(remainder)
            \(signature)
        status: denied
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(headerStart))
        XCTAssertFalse(sanitized.contains(remainder))
        XCTAssertFalse(sanitized.contains(signature))
        XCTAssertTrue(sanitized.contains("status: denied"))
    }

    func testSanitizesJWTSignatureContinuationAfterValidPrefix() {
        let firstFragment = "eyJheader.payload.signatureStart"
        let secondFragment = "remainingSignatureFragment"
        let input = """
        \(firstFragment)
            \(secondFragment)
        status: denied
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("[redacted-jwt]"))
        XCTAssertTrue(sanitized.contains("status: denied"))
    }

    func testSanitizesFiveSegmentCompactJWE() {
        let jwe = [
            "eyJheader",
            "encryptedKey",
            "initializationVector",
            "ciphertextPayload",
            "authenticationTag"
        ].joined(separator: ".")

        XCTAssertEqual(Redactor.sanitize(jwe), "[redacted-jwt]")
    }

    func testSanitizesUnsecuredJWTWithEmptySignature() {
        XCTAssertEqual(
            Redactor.sanitize("eyJheader.payload."),
            "[redacted-jwt]"
        )
    }

    func testSanitizesLongJWTWrappedAcrossMoreThanFourLines() {
        let jwt = "eyJ" + String(repeating: "a", count: 180) + "." +
            String(repeating: "b", count: 180) + "." +
            String(repeating: "c", count: 180)
        let chunks = stride(from: 0, to: jwt.count, by: 80).map { offset -> String in
            let start = jwt.index(jwt.startIndex, offsetBy: offset)
            let end = jwt.index(start, offsetBy: min(80, jwt.count - offset))
            return String(jwt[start..<end])
        }
        let input = ([chunks[0]] + chunks.dropFirst().map { "    \($0)" } + ["status: denied"])
            .joined(separator: "\n")

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains("eyJ" + String(repeating: "a", count: 40)))
        XCTAssertTrue(sanitized.contains("[redacted-jwt]"))
        XCTAssertTrue(sanitized.contains("status: denied"))
    }

    func testSanitizesLowercaseAPIKeyContinuation() {
        let firstFragment = "sk-" + String(repeating: "a", count: 24)
        let secondFragment = String(repeating: "b", count: 24)
        let input = """
        \(firstFragment)
            \(secondFragment)
        status: waiting
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("[redacted-api-key]"))
        XCTAssertTrue(sanitized.contains("status: waiting"))
    }

    func testSanitizesSingleCharacterFinalFragments() {
        let accessKey = "access_" + "token"
        let namedFirstFragment = "opaqueNamedFragment"
        let apiFirstFragment = "sk-" + String(repeating: "a", count: 19)
        let jwtFirstFragment = "eyJheader.payload.s"
        let input = """
        \(accessKey):
          \(namedFirstFragment)
          ~
        \(apiFirstFragment)
            Z
        \(jwtFirstFragment)
            Q
        status: complete
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(namedFirstFragment))
        XCTAssertFalse(sanitized.contains("\n  ~"))
        XCTAssertFalse(sanitized.contains(apiFirstFragment))
        XCTAssertFalse(sanitized.contains("\n    Z"))
        XCTAssertFalse(sanitized.contains(jwtFirstFragment))
        XCTAssertFalse(sanitized.contains("\n    Q"))
        XCTAssertTrue(sanitized.contains("status: complete"))
    }

    func testSanitizesDoubleEscapedWrappedAPIKeyContinuation() {
        let firstFragment = "sk-" + String(repeating: "a", count: 19)
        let escapedQuote = String(repeating: "\\", count: 2) + "\""
        let input = "\(firstFragment)\n    \(escapedQuote)Z\(escapedQuote)\nstatus: complete"

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains("\(escapedQuote)Z\(escapedQuote)"))
        XCTAssertTrue(sanitized.contains("status: complete"))
    }

    func testConservativelyRedactsIndentedTokenShapedLineAfterAPIKey() {
        let apiKey = "sk-" + String(repeating: "a", count: 32)
        let ambiguousLine = "AuthenticationPending"
        let input = """
        \(apiKey)
            \(ambiguousLine)
        status: waiting
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(apiKey))
        XCTAssertFalse(sanitized.contains(ambiguousLine))
        XCTAssertTrue(sanitized.contains("status: waiting"))
    }

    func testDoesNotCrossBlankOrUnindentedLines() {
        let accessKey = "access_" + "token"
        let secret = "opaqueIndentedValue12345"
        let input = """
        \(accessKey):
          \(secret)

        status: still visible
        followupDiagnostic
        """

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertTrue(sanitized.contains("status: still visible"))
        XCTAssertTrue(sanitized.contains("followupDiagnostic"))
    }

    func testDoesNotTreatDiagnosticSentenceAsWrappedSecret() {
        let input = """
        example prefix: sk-
          retrying authentication
        status: waiting
        """

        XCTAssertEqual(Redactor.sanitize(input), input)
    }

    func testDoesNotMatchSecretNamesInsideLargerIdentifiers() {
        let input = """
        monkey_api_key_count=2
        my_access_token_status=missing
        """

        XCTAssertEqual(Redactor.sanitize(input), input)
    }

    func testDoesNotMatchMalformedJWTOrVersionText() {
        let input = """
        eyJonly.two
        eyJnot.a
        version 1.2.3
        """

        XCTAssertEqual(Redactor.sanitize(input), input)
    }

    func testHandlesCRLFWrappedAPIKey() {
        let firstFragment = "sk-" + "proj-d3d3d3d3d3d3"
        let secondFragment = "e4e4e4e4e4e4e4e4e4e4e4e4"
        let input = "credential: \(firstFragment)\r\n    \(secondFragment)\r\nstatus: failed"

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(firstFragment))
        XCTAssertFalse(sanitized.contains(secondFragment))
        XCTAssertTrue(sanitized.contains("status: failed"))
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

    func testSanitizeIsIdempotent() {
        let accessKey = "access_" + "token"
        let secret = "opaque-idempotent-" + String(repeating: "f", count: 20)
        let input = "{\"\(accessKey)\":\"\(secret)\"}"
        let sanitized = Redactor.sanitize(input)

        XCTAssertEqual(Redactor.sanitize(sanitized), sanitized)
    }

    func testDoesNotTrustPlaceholderLikeSecretValues() {
        let accessKey = "access_" + "token"
        let secret = "[redacted-but-real-secret]"
        let input = "\(accessKey)=\(secret)"

        let sanitized = Redactor.sanitize(input)

        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertEqual(sanitized, "\(accessKey)=[redacted]")
    }

    func testDoesNotTrustPlaceholderFollowedBySecretText() {
        let accessKey = "access_" + "token"
        let secret = "REAL_" + "SECRET"

        XCTAssertEqual(
            Redactor.sanitize("\(accessKey)=[redacted] \(secret)"),
            "\(accessKey)=[redacted]"
        )
        XCTAssertEqual(
            Redactor.sanitize("\(accessKey)=[redacted]   , status=ok"),
            "\(accessKey)=[redacted]"
        )
    }

    func testUsesPlaceholderForBlankOutput() {
        XCTAssertEqual(Redactor.sanitize(" \n\t"), L10n.text("redactor.no_output"))
    }
}
