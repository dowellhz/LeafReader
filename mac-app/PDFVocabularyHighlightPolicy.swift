import Foundation

enum PDFVocabularyHighlightPolicy {
    static let batchSize = 8

    static func visibleRecordIndexes(
        pageIndexes: [Int],
        visiblePageIndexes: Set<Int>
    ) -> [Int] {
        guard !visiblePageIndexes.isEmpty else { return [] }
        return pageIndexes.indices.filter { visiblePageIndexes.contains(pageIndexes[$0]) }
    }

    static func batchRange(startIndex: Int, count: Int) -> Range<Int>? {
        guard startIndex >= 0, startIndex < count else { return nil }
        return startIndex..<min(startIndex + batchSize, count)
    }
}
