import Foundation
import PDFKit

extension ReaderAIContextBuilder {
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

    static func pdfPageTranslationText(pageTexts: [String], pageIndex: Int, title: String) -> String {
        guard pageTexts.indices.contains(pageIndex) else { return "" }
        let currentRaw = pageTexts[pageIndex]
        let previousPreviousRaw = pageIndex > 1 ? pageTexts[pageIndex - 2] : ""
        let previousRaw = pageIndex > 0 ? pageTexts[pageIndex - 1] : ""
        let nextRaw = pageIndex + 1 < pageTexts.count ? pageTexts[pageIndex + 1] : ""
        let nextNextRaw = pageIndex + 2 < pageTexts.count ? pageTexts[pageIndex + 2] : ""
        let currentText = stripPDFPageChrome(
            from: currentRaw,
            previousText: previousRaw,
            nextText: nextRaw,
            title: title
        )
        guard hasTrimmedText(currentText) else { return "" }

        let previousText = pageIndex > 0
            ? stripPDFPageChrome(
                from: previousRaw,
                previousText: previousPreviousRaw,
                nextText: currentRaw,
                title: title
            )
            : ""
        let nextText = pageIndex + 1 < pageTexts.count
            ? stripPDFPageChrome(
                from: nextRaw,
                previousText: currentRaw,
                nextText: nextNextRaw,
                title: title
            )
            : ""
        let prefix = pdfPreviousPageParagraphTailIfNeeded(
            currentText: currentText,
            previousText: previousText,
            title: title
        )
        let suffix = pdfNextPageParagraphHeadIfNeeded(
            currentText: currentText,
            nextText: nextText,
            title: title
        )
        let combined = joinedNonEmptyParagraphs([prefix, currentText, suffix])
        return stripPDFPageChrome(
            from: combined,
            previousText: previousRaw,
            nextText: nextRaw,
            title: title
        )
    }

    static func stripPDFPageChrome(from text: String, previousText: String, nextText: String, title: String = "") -> String {
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

    static func pdfTextAppearsToStartMidParagraph(_ text: String) -> Bool {
        let lines = nonEmptyTrimmedLines(from: text)
        guard let firstLine = lines.first, let first = firstLine.first else { return false }
        if ",;:，；：)]）".contains(first) { return true }
        if first.isLowercase { return true }
        return firstLine.range(of: #"^(and|but|or|nor|for|so|yet|because|while|when|which|that|who|whom|whose|where|as|if|then|than|to|of|in|on|with|from|by)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func pdfTextAppearsToEndMidParagraph(_ text: String) -> Bool {
        let lines = nonEmptyTrimmedLines(from: text)
        guard let lastLine = lines.last, let last = lastLine.last else { return false }
        if ".!?。！？”’\"')）".contains(last) { return false }
        if lastLine.range(of: #"[-–—]\s*$"#, options: .regularExpression) != nil { return true }
        return lastLine.count >= 40 && last.isLetter
    }
}
