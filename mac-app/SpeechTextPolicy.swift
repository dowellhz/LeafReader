import Foundation

enum SpeechTextPolicy {
    private static let maxSentenceLength = 520
    private static let maxMergedSegmentLength = 420
    private static let maxChineseSegmentLength = 120
    private static let minSegmentWordCount = 18

    static func readAloudSegments(for text: String) -> [String] {
        segments(for: normalizedReadAloudInput(text))
    }

    static func segments(for text: String) -> [String] {
        if prefersChineseTTS(text) {
            return chineseSegments(for: text)
        }

        let sentenceUnits = englishSentenceUnits(for: text).flatMap(splitLongSentence)
        return mergedShortSegments(sentenceUnits.isEmpty ? [text] : sentenceUnits)
    }

    private static func chineseSegments(for text: String) -> [String] {
        var sentenceUnits: [String] = []
        var current = ""
        func flushCurrent() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                sentenceUnits.append(contentsOf: splitLongChineseSentence(value))
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if "。！？；.!?;".contains(character) {
                flushCurrent()
            }
        }
        flushCurrent()

        return mergedChineseSegments(sentenceUnits.isEmpty ? [text] : sentenceUnits)
    }

    private static func mergedChineseSegments(_ segments: [String]) -> [String] {
        var merged: [String] = []
        var current = ""
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let candidate = current.isEmpty ? trimmed : "\(current) \(trimmed)"
            if !current.isEmpty, candidate.count > maxChineseSegmentLength {
                merged.append(current)
                current = trimmed
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            merged.append(current)
        }
        return merged
    }

    private static func splitLongChineseSentence(_ sentence: String) -> [String] {
        guard sentence.count > maxChineseSegmentLength else {
            return [sentence]
        }

        let softSplit = splitChineseSentence(sentence, delimiters: "，、：:,")
        let chunks = softSplit.flatMap { chunk in
            chunk.count > maxChineseSegmentLength
                ? splitByCharacterLimit(chunk, limit: maxChineseSegmentLength)
                : [chunk]
        }
        return chunks.isEmpty ? [sentence] : chunks
    }

    private static func splitChineseSentence(_ sentence: String, delimiters: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if delimiters.contains(character) {
                let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    chunks.append(value)
                }
                current = ""
            }
        }
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            chunks.append(value)
        }
        return chunks
    }

    private static func splitByCharacterLimit(_ text: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            if current.count >= limit {
                chunks.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
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

    static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}
