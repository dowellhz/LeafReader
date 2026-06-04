import Foundation

enum VocabularyTextPolicy {
    private static let wordTokenPattern = #"[A-Za-z](?:[A-Za-z]|['’–—-](?=[A-Za-z]))*"#
    private static let singleWordPattern = #"^"# + wordTokenPattern + #"$"#
    private static let vocabularySelectionPattern = #"^"# + wordTokenPattern + #"(\s+"# + wordTokenPattern + #"){0,4}$"#
    private static let wordBoundaryBefore = #"(?<![A-Za-z'’–—-])"#
    private static let wordBoundaryAfter = #"(?![A-Za-z'’–—-])"#

    static let maxSingleWordLength = 40
    static let maxVocabularySelectionLength = 80

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedVocabularyText(_ text: String) -> String {
        collapsedWhitespace(joinLineBrokenHyphens(text))
    }

    static func normalizedPDFVocabularyText(
        _ text: String,
        isKnownWord: (String) -> Bool = { _ in false }
    ) -> String {
        guard containsLineBrokenHyphen(text) else {
            return normalizedVocabularyText(text)
        }
        let candidates = lineBrokenHyphenNormalizationCandidates(for: text)
        let dehyphenated = candidates.dehyphenated
        let hyphenated = candidates.hyphenated
        if isSingleEnglishWord(dehyphenated),
           (isKnownWord(dehyphenated) || shouldPreferDehyphenatedLineBreak(original: text, dehyphenated: dehyphenated)) {
            return dehyphenated
        }
        return hyphenated
    }

    static func isSingleEnglishWord(_ text: String) -> Bool {
        let value = normalizedVocabularyText(text)
        guard value.count <= maxSingleWordLength else { return false }
        return value.range(of: singleWordPattern, options: .regularExpression) != nil
    }

    static func speakableWord(_ text: String) -> String? {
        let value = normalizedVocabularyText(text)
        return isSingleEnglishWord(value) ? value : nil
    }

    static func isVocabularySelection(_ text: String) -> Bool {
        let value = normalizedVocabularyText(text)
        guard value.count <= maxVocabularySelectionLength else { return false }
        let words = value.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return value.range(of: vocabularySelectionPattern, options: .regularExpression) != nil
    }

    static func shouldUseSystemTTSForShortSelection(_ text: String) -> Bool {
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
        guard (1...4).contains(words.count) else { return false }
        return text.range(of: #"[.!?]"#, options: .regularExpression) == nil
    }

    static func boundedSearchPattern(for query: String) -> String? {
        let value = normalized(query)
        guard !value.isEmpty else { return nil }
        let words = value.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard !words.isEmpty else { return nil }
        let escaped = words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        return #"(?i)"# + wordBoundaryBefore + escaped + wordBoundaryAfter
    }

    static func boundedPrefixPattern(for prefix: String) -> String {
        wordBoundaryBefore + NSRegularExpression.escapedPattern(for: normalized(prefix))
    }

    static func lineBrokenHyphenWordPattern(prefix: String) -> String {
        boundedPrefixPattern(for: prefix) + #"[‐‑‒–—-]\s*"# + wordTokenPattern
    }

    static func pdfSearchQueries(for query: String) -> [String] {
        let value = normalized(query)
        guard !value.isEmpty else { return [] }

        let joined = collapsedWhitespace(joinLineBrokenHyphens(value))
        var results: [String] = []
        appendUnique(value, to: &results)
        appendUnique(collapsedWhitespace(value), to: &results)
        appendUnique(joined, to: &results)
        for lineBreakVariant in lineBreakHyphenVariants(for: joined) {
            appendUnique(lineBreakVariant, to: &results)
        }
        return results
    }

    static func lineBrokenDehyphenatedSearchPattern(for query: String) -> String? {
        let value = normalized(query)
        guard isSingleEnglishWord(value), !value.contains("-"), value.count >= 4 else {
            return nil
        }
        let characters = Array(value)
        let variants = (1..<characters.count).map { index in
            NSRegularExpression.escapedPattern(for: String(characters[..<index]))
                + #"[‐‑‒–—-]\s*"#
                + NSRegularExpression.escapedPattern(for: String(characters[index...]))
        }
        guard !variants.isEmpty else { return nil }
        return #"(?i)"# + wordBoundaryBefore + "(?:" + variants.joined(separator: "|") + ")" + wordBoundaryAfter
    }

    static func emphasisPattern(for word: String) -> String {
        let value = normalized(word)
        let escaped = NSRegularExpression.escapedPattern(for: value)
        guard isSingleEnglishWord(value) else { return escaped }
        return wordBoundaryBefore + escaped + wordBoundaryAfter
    }

    private static func collapsedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsLineBrokenHyphen(_ value: String) -> Bool {
        value.range(of: #"[‐‑‒–—-]\s+"#, options: .regularExpression) != nil
    }

    private static func lineBrokenHyphenNormalizationCandidates(for value: String) -> (hyphenated: String, dehyphenated: String) {
        (
            hyphenated: collapsedWhitespace(joinLineBrokenHyphens(value)),
            dehyphenated: collapsedWhitespace(removeLineBrokenHyphens(value))
        )
    }

    private static func joinLineBrokenHyphens(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLineBrokenHyphens(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldPreferDehyphenatedLineBreak(original: String, dehyphenated: String) -> Bool {
        guard isSingleEnglishWord(dehyphenated),
              let match = original.range(of: #"(?i)[A-Za-z]+[‐‑‒–—-]\s+[A-Za-z]+"#, options: .regularExpression) else {
            return false
        }
        let prefix = String(original[match])
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+.*$"#, with: "", options: .regularExpression)
        return prefix.count <= 3
    }

    private static func lineBreakHyphenVariants(for value: String) -> [String] {
        let normalizedValue = collapsedWhitespace(value)
        guard normalizedValue.contains("-") else { return [] }
        return [
            normalizedValue.replacingOccurrences(of: "-", with: "-\n"),
            normalizedValue.replacingOccurrences(of: "-", with: "- ")
        ]
    }

    private static func appendUnique(_ value: String, to results: inout [String]) {
        guard !value.isEmpty else { return }
        if !results.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            results.append(value)
        }
    }
}
