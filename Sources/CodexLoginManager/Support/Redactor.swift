import Foundation

enum Redactor {
    private struct Line {
        let contentRange: NSRange
        let indentation: Int
    }

    private struct Replacement {
        let range: NSRange
        let value: String
    }

    private enum WrappedSecretKind {
        case apiKey
        case jwt

        var startExpression: NSRegularExpression {
            switch self {
            case .apiKey:
                return Redactor.apiKeyStartExpression
            case .jwt:
                return Redactor.jwtStartExpression
            }
        }

        var compactExpression: NSRegularExpression {
            switch self {
            case .apiKey:
                return Redactor.compactAPIKeyExpression
            case .jwt:
                return Redactor.compactJWTExpression
            }
        }

        var replacement: String {
            switch self {
            case .apiKey:
                return "[redacted-api-key]"
            case .jwt:
                return "[redacted-jwt]"
            }
        }

        func allows(_ character: unichar) -> Bool {
            if Redactor.isASCIIAlphaNumeric(character) || character == 95 || character == 45 {
                return true
            }

            return self == .jwt && character == 46
        }
    }

    private static let secretKeySource =
        #"(?:openai[ _-]?api[ _-]?key|x[ _-]?(?:access|refresh)[ _-]?token|oauth[ _-]?token|access[ _-]?token|refresh[ _-]?token|id[ _-]?token|api[ _-]?key|proxy[ _-]?authorization|authorization|bearer[ _-]?token|client[ _-]?secret)"#

    private static let namedPrefixExpression = try! NSRegularExpression(
        pattern:
            #"(?i)(?<![A-Za-z0-9_-])(\\*)(["']?)"# +
            secretKeySource +
            #"\1\2(?![A-Za-z0-9_-])[ \t]*[:=][ \t]*"#
    )

    private static let apiKeyStartExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])sk-"#
    )

    private static let jwtStartExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])eyJ"#
    )

    private static let compactAPIKeyExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])"#
    )

    private static let compactJWTExpression = try! NSRegularExpression(
        pattern:
            #"(?<![A-Za-z0-9_-])(?:"# +
            #"eyJ[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}"# +
            #"|eyJ[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*"# +
            #")(?![A-Za-z0-9_.-])"#
    )

    static func sanitize(_ text: String) -> String {
        var sanitized = redactNamedFields(in: text)
        sanitized = redactWrappedSecrets(in: sanitized, kind: .jwt)
        sanitized = redactWrappedSecrets(in: sanitized, kind: .apiKey)
        sanitized = replaceMatches(
            of: compactJWTExpression,
            in: sanitized,
            with: "[redacted-jwt]"
        )
        sanitized = replaceMatches(
            of: compactAPIKeyExpression,
            in: sanitized,
            with: "[redacted-api-key]"
        )

        let visibleText = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleText.isEmpty ? L10n.text("redactor.no_output") : visibleText
    }

    private static func redactNamedFields(in text: String) -> String {
        let source = text as NSString
        let lines = makeLines(in: source)
        var replacements: [Replacement] = []

        for (lineIndex, line) in lines.enumerated() {
            let matches = namedPrefixExpression.matches(
                in: text,
                range: line.contentRange
            )

            for (matchIndex, match) in matches.enumerated() {
                let valueStart = NSMaxRange(match.range)
                let redactsUnquotedLine = source.substring(with: match.range)
                    .localizedCaseInsensitiveContains("authorization")
                let nextFieldStart = !redactsUnquotedLine && matchIndex + 1 < matches.count
                    ? matches[matchIndex + 1].range.location
                    : nil
                let valueResult = namedValueRange(
                    startingAt: valueStart,
                    endingBefore: nextFieldStart,
                    redactingUnquotedLine: redactsUnquotedLine,
                    in: line,
                    source: source
                )

                if let valueRange = valueResult.range {
                    replacements.append(Replacement(range: valueRange, value: "[redacted]"))
                }

                guard valueResult.mayContinue else {
                    continue
                }

                replacements.append(contentsOf: continuationReplacements(
                    after: lineIndex,
                    lines: lines,
                    source: source,
                    baseIndentation: line.indentation,
                    minimumFragmentLength: 1,
                    replacement: "[redacted]"
                ))
            }
        }

        return applying(replacements, to: text)
    }

    private static func namedValueRange(
        startingAt valueStart: Int,
        endingBefore nextFieldStart: Int?,
        redactingUnquotedLine: Bool,
        in line: Line,
        source: NSString
    ) -> (range: NSRange?, mayContinue: Bool) {
        let canContinuePastLine = nextFieldStart == nil
        let lineEnd = min(nextFieldStart ?? Int.max, NSMaxRange(line.contentRange))
        guard valueStart < lineEnd else {
            return (nil, canContinuePastLine)
        }

        let firstCharacter = source.character(at: valueStart)
        if firstCharacter == 34 || firstCharacter == 39 {
            if let closingQuote = closingQuote(
                firstCharacter,
                after: valueStart,
                before: lineEnd,
                source: source
            ) {
                return (
                    NSRange(location: valueStart + 1, length: closingQuote - valueStart - 1),
                    false
                )
            }

            let fragment = trimmedRange(
                from: valueStart + 1,
                to: lineEnd,
                source: source
            )
            return (fragment.length > 0 ? fragment : nil, canContinuePastLine)
        }

        if firstCharacter == 92,
           valueStart + 1 < lineEnd {
            let quote = source.character(at: valueStart + 1)
            if (quote == 34 || quote == 39),
               let closingEscape = closingEscapedQuote(
                   quote,
                   after: valueStart + 1,
                   before: lineEnd,
                   source: source
               ) {
                let range = NSRange(
                    location: valueStart + 2,
                    length: closingEscape - valueStart - 2
                )
                return (range.length > 0 ? range : nil, false)
            }
        }

        if redactingUnquotedLine {
            let range = trimmedRange(
                from: valueStart,
                to: NSMaxRange(line.contentRange),
                source: source
            )
            return (range.length > 0 ? range : nil, false)
        }

        let remainingText = source.substring(with: NSRange(
            location: valueStart,
            length: lineEnd - valueStart
        ))
        if startsWithRecognizedPlaceholder(remainingText) {
            return (nil, false)
        }

        let valueRange = trimmedRange(from: valueStart, to: lineEnd, source: source)
        return (
            valueRange.length > 0 ? valueRange : nil,
            canContinuePastLine
        )
    }

    private static func redactWrappedSecrets(
        in text: String,
        kind: WrappedSecretKind
    ) -> String {
        let source = text as NSString
        let lines = makeLines(in: source)
        var replacements: [Replacement] = []

        for (lineIndex, line) in lines.enumerated() {
            let matches = kind.startExpression.matches(in: text, range: line.contentRange)

            for match in matches {
                let lineEnd = NSMaxRange(line.contentRange)
                let firstRange = wrappedTokenRange(
                    startingAt: match.range.location,
                    before: lineEnd,
                    source: source,
                    kind: kind
                )
                guard firstRange.length > 0 else { continue }

                var candidateRanges = [firstRange]
                var nextLineIndex = lineIndex + 1

                while nextLineIndex < lines.count {
                    let nextLine = lines[nextLineIndex]
                    guard nextLine.indentation > line.indentation,
                          let continuation = wrappedContinuationRange(
                              in: nextLine,
                              source: source,
                              kind: kind
                          ) else {
                        break
                    }

                    candidateRanges.append(continuation)
                    nextLineIndex += 1
                }

                let candidate = candidateRanges
                    .map { source.substring(with: $0) }
                    .joined()
                guard matchesWholeString(candidate, expression: kind.compactExpression) else {
                    continue
                }

                replacements.append(Replacement(range: firstRange, value: kind.replacement))
                replacements.append(contentsOf: candidateRanges.dropFirst().map {
                    Replacement(range: $0, value: "")
                })
            }
        }

        return applying(replacements, to: text)
    }

    private static func continuationReplacements(
        after lineIndex: Int,
        lines: [Line],
        source: NSString,
        baseIndentation: Int,
        minimumFragmentLength: Int,
        replacement: String
    ) -> [Replacement] {
        var replacements: [Replacement] = []
        var nextLineIndex = lineIndex + 1

        while nextLineIndex < lines.count {
            let line = lines[nextLineIndex]
            guard line.indentation > baseIndentation,
                  let coreRange = opaqueContinuationRange(in: line, source: source),
                  coreRange.length >= minimumFragmentLength else {
                break
            }

            replacements.append(Replacement(range: coreRange, value: replacement))
            nextLineIndex += 1
        }

        return replacements
    }

    private static func opaqueContinuationRange(
        in line: Line,
        source: NSString
    ) -> NSRange? {
        var start = line.contentRange.location + line.indentation
        let end = NSMaxRange(line.contentRange)

        guard start < end else { return nil }

        let contentStart = quotedContentStart(at: start, before: end, source: source) ?? start
        if let closingQuoteStart = structuralClosingQuoteStart(
            after: contentStart,
            before: end,
            source: source
        ) {
            let range = trimmedRange(
                from: contentStart,
                to: closingQuoteStart,
                source: source
            )
            return range.length > 0 ? range : nil
        }
        start = contentStart

        var valueEnd = start
        while valueEnd < end && isVisibleASCII(source.character(at: valueEnd)) {
            valueEnd += 1
        }

        guard valueEnd > start else { return nil }
        return NSRange(location: start, length: valueEnd - start)
    }

    private static func wrappedContinuationRange(
        in line: Line,
        source: NSString,
        kind: WrappedSecretKind
    ) -> NSRange? {
        var start = line.contentRange.location + line.indentation
        let lineEnd = NSMaxRange(line.contentRange)
        guard start < lineEnd else { return nil }

        start = quotedContentStart(at: start, before: lineEnd, source: source) ?? start

        let range = wrappedTokenRange(
            startingAt: start,
            before: lineEnd,
            source: source,
            kind: kind
        )
        guard range.length > 0 else { return nil }

        var remainderStart = NSMaxRange(range)
        if structuralClosingQuoteStart(
            after: remainderStart,
            before: lineEnd,
            source: source
        ) == remainderStart {
            return range
        }
        while remainderStart < lineEnd && isHorizontalWhitespace(source.character(at: remainderStart)) {
            remainderStart += 1
        }

        if remainderStart == lineEnd || isNamedValueDelimiter(source.character(at: remainderStart)) {
            return range
        }
        return nil
    }

    private static func wrappedTokenRange(
        startingAt start: Int,
        before end: Int,
        source: NSString,
        kind: WrappedSecretKind
    ) -> NSRange {
        var cursor = start
        while cursor < end && kind.allows(source.character(at: cursor)) {
            cursor += 1
        }
        return NSRange(location: start, length: cursor - start)
    }

    private static func trimmedRange(
        from start: Int,
        to end: Int,
        source: NSString
    ) -> NSRange {
        var trimmedEnd = end
        while trimmedEnd > start && isHorizontalWhitespace(source.character(at: trimmedEnd - 1)) {
            trimmedEnd -= 1
        }
        return NSRange(location: start, length: trimmedEnd - start)
    }

    private static func closingQuote(
        _ quote: unichar,
        after openingQuote: Int,
        before end: Int,
        source: NSString
    ) -> Int? {
        var cursor = openingQuote + 1
        while cursor < end {
            if source.character(at: cursor) == quote {
                var backslashCount = 0
                var previous = cursor - 1
                while previous > openingQuote && source.character(at: previous) == 92 {
                    backslashCount += 1
                    previous -= 1
                }

                if backslashCount.isMultiple(of: 2) {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func closingEscapedQuote(
        _ quote: unichar,
        after openingQuote: Int,
        before end: Int,
        source: NSString
    ) -> Int? {
        var cursor = openingQuote + 1
        while cursor + 1 < end {
            if source.character(at: cursor) == 92,
               source.character(at: cursor + 1) == quote {
                var suffixStart = cursor + 2
                while suffixStart < end && isHorizontalWhitespace(source.character(at: suffixStart)) {
                    suffixStart += 1
                }

                if suffixStart == end || isNamedValueDelimiter(source.character(at: suffixStart)) {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func quotedContentStart(
        at start: Int,
        before end: Int,
        source: NSString
    ) -> Int? {
        var cursor = start
        while cursor < end && source.character(at: cursor) == 92 {
            cursor += 1
        }

        guard cursor < end,
              source.character(at: cursor) == 34 || source.character(at: cursor) == 39 else {
            return nil
        }
        return cursor + 1
    }

    private static func structuralClosingQuoteStart(
        after start: Int,
        before end: Int,
        source: NSString
    ) -> Int? {
        var cursor = start
        while cursor < end {
            let character = source.character(at: cursor)
            guard character == 34 || character == 39 else {
                cursor += 1
                continue
            }

            var quoteStart = cursor
            while quoteStart > start && source.character(at: quoteStart - 1) == 92 {
                quoteStart -= 1
            }

            var suffixStart = cursor + 1
            while suffixStart < end && isHorizontalWhitespace(source.character(at: suffixStart)) {
                suffixStart += 1
            }

            if suffixStart == end || isNamedValueDelimiter(source.character(at: suffixStart)) {
                return quoteStart
            }
            cursor += 1
        }
        return nil
    }

    private static func makeLines(in source: NSString) -> [Line] {
        guard source.length > 0 else { return [] }

        var lines: [Line] = []
        var location = 0

        while location < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )

            var indentation = 0
            while lineStart + indentation < contentsEnd &&
                    isHorizontalWhitespace(source.character(at: lineStart + indentation)) {
                indentation += 1
            }

            lines.append(Line(
                contentRange: NSRange(location: lineStart, length: contentsEnd - lineStart),
                indentation: indentation
            ))
            location = lineEnd
        }

        return lines
    }

    private static func replaceMatches(
        of expression: NSRegularExpression,
        in text: String,
        with replacement: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }

    private static func applying(
        _ replacements: [Replacement],
        to text: String
    ) -> String {
        let mutable = NSMutableString(string: text)
        for replacement in coalescing(replacements).reversed() {
            mutable.replaceCharacters(in: replacement.range, with: replacement.value)
        }

        return mutable as String
    }

    private static func coalescing(_ replacements: [Replacement]) -> [Replacement] {
        let sorted = replacements
            .filter { $0.range.location != NSNotFound && $0.range.length > 0 }
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.range.length > $1.range.length
                }
                return $0.range.location < $1.range.location
            }
        var result: [Replacement] = []

        for replacement in sorted {
            guard let previous = result.last,
                  replacement.range.location < NSMaxRange(previous.range) else {
                result.append(replacement)
                continue
            }

            let mergedEnd = max(NSMaxRange(previous.range), NSMaxRange(replacement.range))
            result[result.count - 1] = Replacement(
                range: NSRange(
                    location: previous.range.location,
                    length: mergedEnd - previous.range.location
                ),
                value: previous.value.isEmpty ? replacement.value : previous.value
            )
        }

        return result
    }

    private static func matchesWholeString(
        _ text: String,
        expression: NSRegularExpression
    ) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range)?.range == range
    }

    private static func startsWithRecognizedPlaceholder(_ text: String) -> Bool {
        let placeholders = ["[redacted]", "[redacted-api-key]", "[redacted-jwt]"]
        return placeholders.contains(text.trimmingCharacters(in: .whitespaces))
    }

    private static func isASCIIAlphaNumeric(_ character: unichar) -> Bool {
        (48...57).contains(character) ||
            (65...90).contains(character) ||
            (97...122).contains(character)
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }

    private static func isVisibleASCII(_ character: unichar) -> Bool {
        (33...126).contains(character)
    }

    private static func isNamedValueDelimiter(_ character: unichar) -> Bool {
        character == 44 || character == 59 || character == 38 ||
            character == 93 || character == 125
    }

}
