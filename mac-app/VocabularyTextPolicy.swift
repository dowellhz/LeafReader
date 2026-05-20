import Foundation

enum VocabularyTextPolicy {
    private static let singleWordPattern = #"^[A-Za-z][A-Za-z'’–—-]*$"#
    private static let vocabularySelectionPattern = #"^[A-Za-z][A-Za-z'’–—-]*(\s+[A-Za-z][A-Za-z'’–—-]*){0,4}$"#
    private static let wordBoundaryBefore = #"(?<![A-Za-z'’–—-])"#
    private static let wordBoundaryAfter = #"(?![A-Za-z'’–—-])"#

    static let maxSingleWordLength = 40
    static let maxVocabularySelectionLength = 80

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSingleEnglishWord(_ text: String) -> Bool {
        let value = normalized(text)
        guard value.count <= maxSingleWordLength else { return false }
        return value.range(of: singleWordPattern, options: .regularExpression) != nil
    }

    static func speakableWord(_ text: String) -> String? {
        let value = normalized(text)
        return isSingleEnglishWord(value) ? value : nil
    }

    static func isVocabularySelection(_ text: String) -> Bool {
        let value = normalized(text)
        guard value.count <= maxVocabularySelectionLength else { return false }
        let words = value.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return value.range(of: vocabularySelectionPattern, options: .regularExpression) != nil
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

    static func emphasisPattern(for word: String) -> String {
        let value = normalized(word)
        let escaped = NSRegularExpression.escapedPattern(for: value)
        guard isSingleEnglishWord(value) else { return escaped }
        return wordBoundaryBefore + escaped + wordBoundaryAfter
    }
}
