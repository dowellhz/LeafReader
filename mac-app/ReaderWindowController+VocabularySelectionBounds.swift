import Cocoa
import PDFKit

extension ReaderWindowController {
    func precisePDFSelectionBounds(page: PDFPage, originalBounds: CGRect, queryText: String) -> CGRect? {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 80,
              let pageText = page.string,
              !pageText.isEmpty else {
            return nil
        }

        let candidates = pdfTextRanges(matching: normalizedQuery, in: pageText)
        guard !candidates.isEmpty else { return nil }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestBounds: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for range in candidates {
            guard let candidateSelection = page.selection(for: range) else { continue }
            let candidateBounds = candidateSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
            guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }

            let intersectsOriginal = originalBounds.insetBy(dx: -8, dy: -6).intersects(candidateBounds)
            let candidateCenter = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
            let distance = hypot(candidateCenter.x - originalCenter.x, candidateCenter.y - originalCenter.y)
            let score = intersectsOriginal ? distance : distance + 10_000
            if score < bestScore {
                bestScore = score
                bestBounds = candidateBounds
            }
        }

        return bestBounds
    }

    func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        let words = query.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: #"\s+"#)
        let pattern: String
        if words.count == 1 {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        } else {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)).map(\.range)
    }
}
