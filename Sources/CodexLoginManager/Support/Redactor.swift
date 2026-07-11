import Foundation

enum Redactor {
    private struct Rule {
        let expression: NSRegularExpression
        let replacement: String
    }

    private static let tokenPatterns: [Rule] = [
        Rule(
            expression: try! NSRegularExpression(pattern: #"(?i)(access_token|refresh_token|id_token|api_key|OPENAI_API_KEY)\s*[:=]\s*["']?[^"'\s,}]+"#),
            replacement: "$1: [redacted]"
        ),
        Rule(
            expression: try! NSRegularExpression(pattern: #"sk-[A-Za-z0-9_\-]{20,}"#),
            replacement: "[redacted-api-key]"
        ),
        Rule(
            expression: try! NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#),
            replacement: "[redacted-jwt]"
        )
    ]

    static func sanitize(_ text: String) -> String {
        var sanitized = text
        for rule in tokenPatterns {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            sanitized = rule.expression.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }

        let lines = sanitized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? "无输出" : lines.joined(separator: "\n")
    }
}
