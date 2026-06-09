import CoreGraphics
import Foundation

enum PDFReadAloudChromeFilter {
    final class State {
        private var edgeLineCounts: [String: Int] = [:]
        private let repeatedLineThreshold: Int

        init(repeatedLineThreshold: Int = 2) {
            self.repeatedLineThreshold = max(2, repeatedLineThreshold)
        }

        func reset() {
            edgeLineCounts.removeAll()
        }

        func shouldFilterRepeatedEdgeLine(_ normalized: String) -> Bool {
            let count = (edgeLineCounts[normalized] ?? 0) + 1
            edgeLineCounts[normalized] = count
            return count >= repeatedLineThreshold
        }
    }

    struct Line {
        let text: String
        let bounds: CGRect
        let pageBounds: CGRect
    }

    static func filteredText(
        lines: [Line],
        state: State
    ) -> String {
        var filteredRowKeys = Set<Int>()
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let normalized = normalizedChromeLine(text)
            guard !normalized.isEmpty else { continue }
            if isChromeLine(normalized, line: line, state: state) {
                filteredRowKeys.insert(rowKey(for: line))
            }
        }

        let kept = lines.compactMap { line -> String? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let normalized = normalizedChromeLine(text)
            guard !normalized.isEmpty else { return nil }
            guard !filteredRowKeys.contains(rowKey(for: line)) else {
                return nil
            }
            return text
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isChromeLine(
        _ normalized: String,
        line: Line,
        state: State
    ) -> Bool {
        guard isEdgeLine(line) else { return false }
        if isPageNumberLike(normalized) { return true }
        return state.shouldFilterRepeatedEdgeLine(normalized)
    }

    private static func isEdgeLine(_ line: Line) -> Bool {
        guard !line.pageBounds.isEmpty, !line.bounds.isEmpty else { return false }
        let band = min(max(line.pageBounds.height * 0.16, 36), 96)
        let midY = line.bounds.midY
        return midY >= line.pageBounds.maxY - band || midY <= line.pageBounds.minY + band
    }

    private static func rowKey(for line: Line) -> Int {
        Int((line.bounds.midY / 4).rounded())
    }

    private static func isPageNumberLike(_ normalized: String) -> Bool {
        normalized.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil
    }

    private static func normalizedChromeLine(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
