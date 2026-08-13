import Cocoa
import PDFKit

extension ReaderWindowController {
    func textQuoteAnchor(
        pageIndex: Int,
        selection: PDFSelection,
        page: PDFPage,
        sourceText: String
    ) -> TextQuoteAnchor? {
        let rangeCount = selection.numberOfTextRanges(on: page)
        guard rangeCount > 0 else { return nil }
        var combinedRange = selection.range(at: 0, on: page)
        guard combinedRange.location != NSNotFound else { return nil }
        if rangeCount > 1 {
            for index in 1..<rangeCount {
                let range = selection.range(at: index, on: page)
                guard range.location != NSNotFound else { continue }
                combinedRange = NSUnionRange(combinedRange, range)
            }
        }
        return TextQuoteAnchor(
            unitOrdinal: pageIndex,
            sourceRange: combinedRange,
            sourceText: sourceText
        )
    }

    func vocabularyTextForCurrentPDFSelection(selection: PDFSelection?, fallback: String) -> String {
        let normalizedFallback = normalizedPDFVocabularyText(fallback)
        guard let selection,
              let page = selection.pages.first,
              let pageText = page.string,
              !pageText.isEmpty else {
            return normalizedFallback
        }
        return lineBrokenHyphenWordNearSelection(
            selection: selection,
            page: page,
            pageText: pageText,
            fallback: fallback
        )
            ?? normalizedFallback
    }

    func precisePDFSelectionBounds(page: PDFPage, originalBounds: CGRect, queryText: String) -> CGRect? {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 80,
              let pageText = page.string,
              !pageText.isEmpty else {
            return nil
        }

        let candidates = VocabularyTextPolicy.pdfSearchQueries(for: normalizedQuery)
            .flatMap { pdfTextRanges(matching: $0, in: pageText) }
        guard !candidates.isEmpty else { return nil }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestBounds: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for range in candidates.prefix(36) {
            guard let candidateSelection = page.selection(for: range) else { continue }
            for rawBounds in tightSelectionLineBounds(candidateSelection, page: page, originalBounds: originalBounds) {
                let candidateBounds = rawBounds.insetBy(dx: -1.5, dy: -1)
                guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }

                let score = boundsScore(
                    candidateBounds,
                    originalBounds: originalBounds,
                    originalCenter: originalCenter,
                    intersectionInset: CGSize(width: 8, height: 6)
                )
                if score < bestScore {
                    bestScore = score
                    bestBounds = candidateBounds
                }
            }
        }

        return bestBounds
    }

    func exactPDFSelectionBounds(_ selection: PDFSelection, page: PDFPage) -> CGRect? {
        let originalBounds = selection.bounds(for: page)
        guard originalBounds.width > 0, originalBounds.height > 0 else { return nil }
        let bounds = tightSelectionBounds(
            selection,
            page: page,
            originalBounds: originalBounds
        ).insetBy(dx: -1.5, dy: -1)
        return bounds.width > 0 && bounds.height > 0 ? bounds : nil
    }

    func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        let patterns = [
            VocabularyTextPolicy.boundedSearchPattern(for: query),
            VocabularyTextPolicy.lineBrokenDehyphenatedSearchPattern(for: query)
        ].compactMap { $0 }
        guard !patterns.isEmpty else { return [] }

        var ranges: [NSRange] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)) {
                if !ranges.contains(where: { NSEqualRanges($0, match.range) }) {
                    ranges.append(match.range)
                }
            }
        }
        return ranges
    }

    private func lineBrokenHyphenWordNearSelection(
        selection: PDFSelection,
        page: PDFPage,
        pageText: String,
        fallback: String
    ) -> String? {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String
        if trimmed.range(of: #"[‐‑‒–—-]$"#, options: .regularExpression) != nil {
            let prefix = trimmed.replacingOccurrences(of: #"[‐‑‒–—-]+$"#, with: "", options: .regularExpression)
            guard !prefix.isEmpty else { return nil }
            pattern = VocabularyTextPolicy.lineBrokenHyphenWordPattern(prefix: prefix)
        } else {
            guard VocabularyTextPolicy.isSingleEnglishWord(trimmed) else { return nil }
            pattern = VocabularyTextPolicy.lineBrokenHyphenWordPattern(suffix: trimmed)
        }

        let caseInsensitivePattern = #"(?i)"# + pattern
        guard let regex = try? NSRegularExpression(pattern: caseInsensitivePattern) else { return nil }
        let nsText = pageText as NSString
        let matches = regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        let originalBounds = selection.bounds(for: page)
        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestText: String?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for match in matches.prefix(24) {
            guard let candidateSelection = page.selection(for: match.range) else { continue }
            let candidateBounds = tightSelectionBounds(
                candidateSelection,
                page: page,
                originalBounds: originalBounds
            )
            guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }
            let score = boundsScore(
                candidateBounds,
                originalBounds: originalBounds,
                originalCenter: originalCenter,
                intersectionInset: CGSize(width: 10, height: 8)
            )
            if score < bestScore {
                let matchedText = nsText.substring(with: match.range)
                let layoutHyphenRange = match.range(withName: "layoutHyphen")
                let selectionSpansMultipleLines = candidateSelection.selectionsByLine().count > 1
                let localLayoutHyphenRange: NSRange? =
                    selectionSpansMultipleLines && layoutHyphenRange.location != NSNotFound
                    ? NSRange(
                        location: layoutHyphenRange.location - match.range.location,
                        length: layoutHyphenRange.length
                    )
                    : nil
                let value = normalizedPDFVocabularyText(
                    matchedText,
                    lineBrokenHyphenRange: localLayoutHyphenRange
                )
                if VocabularyTextPolicy.speakableWord(value) != nil {
                    bestScore = score
                    bestText = value
                }
            }
        }

        return bestText
    }

    private func normalizedPDFVocabularyText(_ text: String, lineBrokenHyphenRange: NSRange? = nil) -> String {
        VocabularyTextPolicy.normalizedPDFVocabularyText(
            text,
            lineBrokenHyphenRange: lineBrokenHyphenRange,
            isKnownHyphenatedWord: isKnownVocabularyWord,
            isKnownWord: isKnownVocabularyWord
        )
    }

    private func isKnownVocabularyWord(_ candidate: String) -> Bool {
        let metadata = VocabularyDictionaryMetadataService.metadata(for: candidate)
        return metadata.frequency != nil || metadata.tags != nil
    }

    private func tightSelectionBounds(_ selection: PDFSelection, page: PDFPage, originalBounds: CGRect) -> CGRect {
        tightSelectionLineBounds(selection, page: page, originalBounds: originalBounds).first ?? selection.bounds(for: page)
    }

    private func tightSelectionLineBounds(_ selection: PDFSelection, page: PDFPage, originalBounds: CGRect) -> [CGRect] {
        let lineBounds = selection.selectionsByLine()
            .map { $0.bounds(for: page) }
            .filter { $0.width > 0 && $0.height > 0 }
        guard !lineBounds.isEmpty else { return [selection.bounds(for: page)] }
        guard lineBounds.count > 1 else { return lineBounds }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        return lineBounds.sorted { lhs, rhs in
            let lhsScore = lineBoundsScore(lhs, originalBounds: originalBounds, originalCenter: originalCenter)
            let rhsScore = lineBoundsScore(rhs, originalBounds: originalBounds, originalCenter: originalCenter)
            return lhsScore < rhsScore
        }
    }

    private func lineBoundsScore(_ bounds: CGRect, originalBounds: CGRect, originalCenter: CGPoint) -> CGFloat {
        boundsScore(
            bounds,
            originalBounds: originalBounds,
            originalCenter: originalCenter,
            intersectionInset: CGSize(width: 10, height: 8)
        )
    }

    private func boundsScore(
        _ bounds: CGRect,
        originalBounds: CGRect,
        originalCenter: CGPoint,
        intersectionInset: CGSize
    ) -> CGFloat {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let distance = hypot(center.x - originalCenter.x, center.y - originalCenter.y)
        let intersectsOriginal = originalBounds
            .insetBy(dx: -intersectionInset.width, dy: -intersectionInset.height)
            .intersects(bounds)
        let intersectionPenalty: CGFloat = intersectsOriginal ? 0 : 10_000
        return distance + intersectionPenalty + bounds.width * 0.01
    }
}
