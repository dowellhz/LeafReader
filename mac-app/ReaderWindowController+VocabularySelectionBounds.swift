import Cocoa
import PDFKit

extension ReaderWindowController {
    func vocabularyTextForCurrentPDFSelection(selection: PDFSelection?, fallback: String) -> String {
        let normalizedFallback = VocabularyTextPolicy.normalizedVocabularyText(fallback)
        if VocabularyTextPolicy.speakableWord(normalizedFallback) != nil {
            return normalizedFallback
        }
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

    func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        guard let pattern = VocabularyTextPolicy.boundedSearchPattern(for: query) else { return [] }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)).map(\.range)
    }

    private func lineBrokenHyphenWordNearSelection(
        selection: PDFSelection,
        page: PDFPage,
        pageText: String,
        fallback: String
    ) -> String? {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"[‐‑‒–—-]$"#, options: .regularExpression) != nil else { return nil }
        let prefix = trimmed.replacingOccurrences(of: #"[‐‑‒–—-]+$"#, with: "", options: .regularExpression)
        guard !prefix.isEmpty else { return nil }

        let pattern = #"(?i)"# + VocabularyTextPolicy.lineBrokenHyphenWordPattern(prefix: prefix)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
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
                let value = VocabularyTextPolicy.normalizedVocabularyText(nsText.substring(with: match.range))
                if VocabularyTextPolicy.speakableWord(value) != nil {
                    bestScore = score
                    bestText = value
                }
            }
        }

        return bestText
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
