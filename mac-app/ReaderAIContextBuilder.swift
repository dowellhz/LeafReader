import Foundation

struct ReaderAIContextBuilder {
    static func selectedTextContext(selectedText: String, sourceText: String, radius: Int) -> String? {
        sentenceContext(containing: selectedText, in: sourceText)
            ?? characterWindowContext(containing: selectedText, in: sourceText, radius: radius)
    }

    static func visibleWebTextScript(preserveLineBreaks: Bool) -> String {
        let selector = preserveLineBreaks
            ? "h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,td,th"
            : "h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,td,th,div"
        let surroundingBlockCount = preserveLineBreaks ? 0 : 1
        return """
        (() => {
          const blocks = Array.from(document.body.querySelectorAll('\(selector)'));
          const seen = new Set();
          const parts = [];
          const visibleIndexes = [];
          for (let index = 0; index < blocks.length; index++) {
            const el = blocks[index];
            const rect = el.getBoundingClientRect();
            if (rect.bottom < 0 || rect.top > window.innerHeight || rect.width <= 0 || rect.height <= 0) continue;
            visibleIndexes.push(index);
          }
          if (!visibleIndexes.length) return '';
          const startIndex = Math.max(0, visibleIndexes[0] - \(surroundingBlockCount));
          const endIndex = Math.min(blocks.length - 1, visibleIndexes[visibleIndexes.length - 1] + \(surroundingBlockCount));
          for (let index = startIndex; index <= endIndex; index++) {
            const el = blocks[index];
            const text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
            if (!text || seen.has(text)) continue;
            seen.add(text);
            parts.push(text);
          }
          return parts.join('\\n\\n').slice(0, 8000);
        })();
        """
    }

    static func normalizeVisibleWebText(_ text: String, preserveLineBreaks: Bool) -> String {
        preserveLineBreaks ? normalizeReaderTextPreservingParagraphs(text) : normalizeWhitespace(text)
    }

    static func webProgressTextWindow(plainText: String, progress: Double) -> String {
        let text = normalizeWhitespace(plainText)
        guard !text.isEmpty else { return "" }
        let center = Int(Double(text.count) * progress)
        let lower = max(0, center - 2200)
        let upper = min(text.count, center + 3800)
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeReaderTextPreservingParagraphs(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }

    static func nonEmptyTrimmedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map(trimmed)
            .filter { !$0.isEmpty }
    }

    static func joinedNonEmptyParagraphs(_ parts: [String]) -> String {
        parts
            .filter(hasTrimmedText)
            .joined(separator: "\n\n")
    }

    private static func sentenceContext(containing selectedText: String, in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let sentenceStart = normalizedText[..<range.lowerBound].lastIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.startIndex
        let sentenceEnd = normalizedText[range.upperBound...].firstIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.endIndex
        let sentence = normalizeWhitespace(trimLeadingContextQuotes(String(normalizedText[sentenceStart..<sentenceEnd])))
        guard sentence.count > normalizedSelection.count else { return nil }
        return sentence
    }

    private static func characterWindowContext(containing selectedText: String, in text: String, radius: Int) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let prefixStart = normalizedText.index(range.lowerBound, offsetBy: -radius, limitedBy: normalizedText.startIndex) ?? normalizedText.startIndex
        let suffixEnd = normalizedText.index(range.upperBound, offsetBy: radius, limitedBy: normalizedText.endIndex) ?? normalizedText.endIndex
        return normalizeWhitespace(trimLeadingContextQuotes(String(normalizedText[prefixStart..<suffixEnd])))
    }

    static func trimLeadingContextQuotes(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, #""“”‘’'`"#.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
