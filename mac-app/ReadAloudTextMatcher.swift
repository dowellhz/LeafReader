import Foundation

enum ReadAloudTextMatcher {
    private static let partialTokenWindowSizes = [12, 10, 8, 6, 4]
    private static let minimumPartialQueryTokens = 6
    private static let minimumPartialPageTokens = 4

    static func range(
        of query: String,
        in pageText: String,
        searchRange: NSRange? = nil,
        allowsPartialFallback: Bool = true
    ) -> NSRange? {
        let fullRange = NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)
        let targetRange = searchRange ?? fullRange
        let exactRange = (pageText as NSString).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: targetRange,
            locale: nil
        )
        if exactRange.location != NSNotFound {
            return exactRange
        }

        let parts = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let pattern = parts
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        ) else {
            return nil
        }
        if let match = regex.firstMatch(in: pageText, range: targetRange)?.range {
            return match
        }
        if let looseRange = whitespaceInsensitiveRange(of: query, in: pageText, searchRange: targetRange) {
            return looseRange
        }
        if let tokenRange = tokenRange(of: query, in: pageText, searchRange: targetRange) {
            return tokenRange
        }
        guard allowsPartialFallback else { return nil }
        return partialTokenRange(of: query, in: pageText, searchRange: targetRange)
    }

    private static func whitespaceInsensitiveRange(of query: String, in pageText: String, searchRange: NSRange) -> NSRange? {
        let queryUnits = query
            .filter { !$0.isWhitespace }
            .map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard queryUnits.count >= 2,
              let swiftSearchRange = Range(searchRange, in: pageText) else {
            return nil
        }

        var pageUnits: [(value: String, range: NSRange)] = []
        var index = swiftSearchRange.lowerBound
        while index < swiftSearchRange.upperBound {
            let next = pageText.index(after: index)
            let character = pageText[index]
            if !character.isWhitespace {
                let characterRange = index..<next
                pageUnits.append((
                    value: String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
                    range: NSRange(characterRange, in: pageText)
                ))
            }
            index = next
        }
        guard queryUnits.count <= pageUnits.count else { return nil }

        let lastStart = pageUnits.count - queryUnits.count
        for start in 0...lastStart {
            var matches = true
            for offset in 0..<queryUnits.count where pageUnits[start + offset].value != queryUnits[offset] {
                matches = false
                break
            }
            guard matches else { continue }
            return range(from: pageUnits[start].range, through: pageUnits[start + queryUnits.count - 1].range)
        }
        return nil
    }

    private struct Token {
        let value: String
        let range: NSRange
    }

    private static func tokenRange(of query: String, in pageText: String, searchRange: NSRange) -> NSRange? {
        let queryTokens = tokens(in: query).map(\.value)
        let pageTokens = tokens(in: pageText, searchRange: searchRange)
        return tokenRange(tokens: queryTokens, in: pageTokens)
    }

    private static func partialTokenRange(of query: String, in pageText: String, searchRange: NSRange) -> NSRange? {
        let queryTokens = tokens(in: query).map(\.value)
        guard queryTokens.count >= minimumPartialQueryTokens else { return nil }
        let pageTokens = tokens(in: pageText, searchRange: searchRange)
        guard pageTokens.count >= minimumPartialPageTokens else { return nil }

        for windowSize in partialTokenWindowSizes {
            guard queryTokens.count >= windowSize else { continue }
            let window = Array(queryTokens.prefix(windowSize))
            if let range = tokenRange(tokens: window, in: pageTokens) {
                return range
            }
        }
        return nil
    }

    private static func tokenRange(tokens queryTokens: [String], in pageTokens: [Token]) -> NSRange? {
        guard !queryTokens.isEmpty, queryTokens.count <= pageTokens.count else {
            return nil
        }
        let lastStart = pageTokens.count - queryTokens.count
        for start in 0...lastStart {
            var matches = true
            for offset in 0..<queryTokens.count where pageTokens[start + offset].value != queryTokens[offset] {
                matches = false
                break
            }
            guard matches else { continue }
            let first = pageTokens[start].range
            let last = pageTokens[start + queryTokens.count - 1].range
            return range(from: first, through: last)
        }
        return nil
    }

    private static func range(from first: NSRange, through last: NSRange) -> NSRange {
        NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private static func tokens(in text: String, searchRange: NSRange? = nil) -> [Token] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9]+"#,
            options: [.useUnicodeWordBoundaries]
        ) else {
            return []
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let tokens: [Token] = regex.matches(in: text, range: searchRange ?? fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let value = String(text[range])
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return Token(value: value, range: match.range)
        }
        return tokensMergingLineBreakHyphenation(tokens, in: text)
    }

    private static func tokensMergingLineBreakHyphenation(_ tokens: [Token], in text: String) -> [Token] {
        guard tokens.count >= 2 else { return tokens }
        var merged: [Token] = []
        var index = 0
        while index < tokens.count {
            let current = tokens[index]
            guard index + 1 < tokens.count else {
                merged.append(current)
                break
            }
            let next = tokens[index + 1]
            let separatorRange = NSRange(location: NSMaxRange(current.range), length: next.range.location - NSMaxRange(current.range))
            if separatorRange.length > 0,
               let separator = Range(separatorRange, in: text).map({ String(text[$0]) }),
               shouldMergeTokens(current, next, separatedBy: separator) {
                merged.append(Token(
                    value: current.value + next.value,
                    range: NSRange(location: current.range.location, length: NSMaxRange(next.range) - current.range.location)
                ))
                index += 2
            } else {
                merged.append(current)
                index += 1
            }
        }
        return merged
    }

    private static func shouldMergeTokens(_ current: Token, _ next: Token, separatedBy separator: String) -> Bool {
        if separator.range(of: #"[-\u{2010}-\u{2015}]\s+"#, options: .regularExpression) != nil {
            return true
        }
        let nonDropCapLetters: Set<String> = ["a", "i"]
        return current.value.count == 1
            && !nonDropCapLetters.contains(current.value)
            && next.value.count >= 2
            && separator.range(of: #"^\s+$"#, options: .regularExpression) != nil
    }
}
