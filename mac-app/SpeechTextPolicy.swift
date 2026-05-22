import Foundation

enum SpeechTextPolicy {
    private static let maxSentenceLength = 520
    private static let maxMergedSegmentLength = 420
    private static let minSegmentWordCount = 18

    static func readAloudSegments(for text: String) -> [String] {
        segments(for: normalizedReadAloudInput(text))
    }

    static func isEnglishCandidate(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }
        return !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }

    static func isChineseCandidate(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: Self.isCJK)
    }

    static func isLocalTTSCandidate(_ text: String) -> Bool {
        isEnglishCandidate(text) || isChineseCandidate(text)
    }

    static func normalizedReadAloudInput(_ text: String) -> String {
        if isChineseCandidate(text) {
            return normalizedCommonInput(text)
        }
        return normalizedEnglishInput(text)
    }

    static func normalizedEnglishInput(_ text: String) -> String {
        var value = normalizedPunctuationInput(text)
        value = value.replacingOccurrences(
            of: #"(?i)([A-Za-z])-\s*[\r\n]+\s*([A-Za-z])"#,
            with: "$1$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"([A-Za-z])\s*'\s*([A-Za-z])"#,
            with: "$1'$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(^|[\r\n]+|[.!?]\s+|"\s*)([B-HJ-Zb-hj-z])\s+([a-z]{2,})"#,
            with: "$1$2$3",
            options: .regularExpression
        )
        value = collapseWhitespace(in: value)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedCommonInput(_ text: String) -> String {
        collapseWhitespace(in: normalizedPunctuationInput(text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPunctuationInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
    }

    private static func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(
                of: #"[\r\n\t]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s{2,}"#,
                with: " ",
                options: .regularExpression
            )
    }

    static func segments(for text: String) -> [String] {
        var sentenceUnits: [String] = []
        var current = ""
        func flushCurrent() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                sentenceUnits.append(contentsOf: splitLongSentence(value))
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if ".!?。！？；;".contains(character) {
                flushCurrent()
            }
        }
        flushCurrent()

        return mergedShortSegments(sentenceUnits.isEmpty ? [text] : sentenceUnits)
    }

    private static func mergedShortSegments(_ segments: [String]) -> [String] {
        var merged: [String] = []
        var current = ""
        var currentWordCount = 0
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let candidate = current.isEmpty ? trimmed : "\(current) \(trimmed)"
            if !current.isEmpty, candidate.count > maxMergedSegmentLength {
                merged.append(current)
                current = trimmed
                currentWordCount = wordCount(in: trimmed)
            } else {
                current = candidate
                currentWordCount += wordCount(in: trimmed)
            }

            if currentWordCount >= minSegmentWordCount {
                merged.append(current)
                current = ""
                currentWordCount = 0
            }
        }
        if !current.isEmpty {
            if let last = merged.last,
               "\(last) \(current)".count <= maxMergedSegmentLength {
                merged[merged.count - 1] = "\(last) \(current)"
            } else {
                merged.append(current)
            }
        }
        return merged
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        guard sentence.count > maxSentenceLength else {
            return [sentence]
        }

        var segments: [String] = []
        var current = ""
        for word in sentence.split(separator: " ") {
            let next = current.isEmpty ? String(word) : "\(current) \(word)"
            if next.count > maxSentenceLength, !current.isEmpty {
                segments.append(current)
                current = String(word)
            } else {
                current = next
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments.isEmpty ? [sentence] : segments
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
            return true
        default:
            return false
        }
    }
}
