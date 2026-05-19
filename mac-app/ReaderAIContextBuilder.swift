import Foundation
import PDFKit

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

    static func pdfPageSummaryText(document: PDFDocument, page: PDFPage) -> String {
        let pageIndex = document.index(for: page)
        let currentText = page.string ?? ""
        guard hasTrimmedText(currentText) else { return "" }

        let previousText = pageIndex > 0 ? document.page(at: pageIndex - 1)?.string ?? "" : ""
        let nextText = pageIndex + 1 < document.pageCount ? document.page(at: pageIndex + 1)?.string ?? "" : ""

        let prefix = pdfPreviousPageParagraphTailIfNeeded(currentText: currentText, previousText: previousText)
        let suffix = pdfNextPageParagraphHeadIfNeeded(currentText: currentText, nextText: nextText)
        return joinedNonEmptyParagraphs([prefix, currentText, suffix])
    }

    static func pdfPageTranslationText(document: PDFDocument, page: PDFPage, title: String) -> String {
        let pageIndex = document.index(for: page)
        let previousPreviousRaw = pageIndex > 1 ? document.page(at: pageIndex - 2)?.string ?? "" : ""
        let previousRaw = pageIndex > 0 ? document.page(at: pageIndex - 1)?.string ?? "" : ""
        let nextRaw = pageIndex + 1 < document.pageCount ? document.page(at: pageIndex + 1)?.string ?? "" : ""
        let nextNextRaw = pageIndex + 2 < document.pageCount ? document.page(at: pageIndex + 2)?.string ?? "" : ""
        let currentText = stripPDFPageChrome(from: page.string ?? "", previousText: previousRaw, nextText: nextRaw, title: title)
        guard hasTrimmedText(currentText) else { return "" }

        let previousText = pageIndex > 0 ? stripPDFPageChrome(from: previousRaw, previousText: previousPreviousRaw, nextText: page.string ?? "", title: title) : ""
        let nextText = pageIndex + 1 < document.pageCount ? stripPDFPageChrome(from: nextRaw, previousText: page.string ?? "", nextText: nextNextRaw, title: title) : ""
        let prefix = pdfPreviousPageParagraphTailIfNeeded(currentText: currentText, previousText: previousText, title: title)
        let suffix = pdfNextPageParagraphHeadIfNeeded(currentText: currentText, nextText: nextText, title: title)
        let combined = joinedNonEmptyParagraphs([prefix, currentText, suffix])
        return stripPDFPageChrome(from: combined, previousText: previousRaw, nextText: nextRaw, title: title)
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

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }

    private static func nonEmptyTrimmedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map(trimmed)
            .filter { !$0.isEmpty }
    }

    private static func joinedNonEmptyParagraphs(_ parts: [String]) -> String {
        parts
            .filter(hasTrimmedText)
            .joined(separator: "\n\n")
    }

    private static func stripPDFPageChrome(from text: String, previousText: String, nextText: String, title: String = "") -> String {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(trimmed)
        let previousEdges = pdfEdgeLines(previousText)
        let nextEdges = pdfEdgeLines(nextText)

        func isRepeatedPageChrome(_ normalized: String) -> Bool {
            normalized == normalizePDFChromeLine(title)
                || previousEdges.contains(normalized)
                || nextEdges.contains(normalized)
        }

        func isPageNumberLike(_ normalized: String) -> Bool {
            normalized.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil
                || normalized.range(of: #"^[-–—]?\d{1,4}[-–—]?$"#, options: .regularExpression) != nil
        }

        func isChromeLine(_ line: String, edgeOnly: Bool) -> Bool {
            let normalized = normalizePDFChromeLine(line)
            guard !normalized.isEmpty else { return true }
            if isRepeatedPageChrome(normalized) { return true }
            if edgeOnly, isPageNumberLike(normalized) { return true }
            return false
        }

        for index in lines.indices.reversed() {
            let edgeOnly = index < 6 || index >= max(0, lines.count - 6)
            if isChromeLine(lines[index], edgeOnly: edgeOnly) {
                lines.remove(at: index)
            }
        }
        for index in lines.indices.prefix(3).reversed() where lines.indices.contains(index) && isChromeLine(lines[index], edgeOnly: true) {
            lines.remove(at: index)
        }
        for index in lines.indices.suffix(3).reversed() where lines.indices.contains(index) && isChromeLine(lines[index], edgeOnly: true) {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    private static func pdfEdgeLines(_ text: String) -> Set<String> {
        let lines = text
            .components(separatedBy: .newlines)
            .map { normalizePDFChromeLine($0) }
            .filter { !$0.isEmpty }
        return Set(lines.prefix(3) + lines.suffix(3))
    }

    private static func normalizePDFChromeLine(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pdfPreviousPageParagraphTailIfNeeded(currentText: String, previousText: String, title: String = "") -> String {
        guard !previousText.isEmpty, pdfTextAppearsToStartMidParagraph(currentText) else { return "" }
        let normalized = trimmed(previousText)
        guard !normalized.isEmpty else { return "" }
        let start = normalized.lastIndex { "\n\r.!?。！？".contains($0) }
            .map { normalized.index(after: $0) } ?? normalized.startIndex
        return trimmed(stripPDFPageChrome(from: String(normalized[start...]), previousText: "", nextText: currentText, title: title))
    }

    private static func pdfNextPageParagraphHeadIfNeeded(currentText: String, nextText: String, title: String = "") -> String {
        guard !nextText.isEmpty, pdfTextAppearsToEndMidParagraph(currentText) else { return "" }
        let normalized = trimmed(nextText)
        guard !normalized.isEmpty else { return "" }
        let end = normalized.firstIndex { ".!?。！？\n\r".contains($0) }
            .map { normalized.index(after: $0) } ?? normalized.endIndex
        return trimmed(stripPDFPageChrome(from: String(normalized[..<end]), previousText: currentText, nextText: "", title: title))
    }

    private static func pdfTextAppearsToStartMidParagraph(_ text: String) -> Bool {
        let lines = nonEmptyTrimmedLines(from: text)
        guard let firstLine = lines.first, let first = firstLine.first else { return false }
        if ",;:，；：)]）".contains(first) { return true }
        if first.isLowercase { return true }
        return firstLine.range(of: #"^(and|but|or|nor|for|so|yet|because|while|when|which|that|who|whom|whose|where|as|if|then|than|to|of|in|on|with|from|by)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func pdfTextAppearsToEndMidParagraph(_ text: String) -> Bool {
        let lines = nonEmptyTrimmedLines(from: text)
        guard let lastLine = lines.last, let last = lastLine.last else { return false }
        if ".!?。！？”’\"')）".contains(last) { return false }
        if lastLine.range(of: #"[-–—]\s*$"#, options: .regularExpression) != nil { return true }
        return lastLine.count >= 40 && last.isLetter
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
        let sentence = normalizeWhitespace(String(normalizedText[sentenceStart..<sentenceEnd]))
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
        return normalizeWhitespace(String(normalizedText[prefixStart..<suffixEnd]))
    }
}
