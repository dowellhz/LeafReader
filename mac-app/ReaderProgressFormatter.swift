import Foundation

enum ReaderProgressFormatter {
    static func pdfPageText(pageIndex: Int, pageCount: Int) -> String {
        let safePageCount = max(1, pageCount)
        let safePageIndex = min(max(pageIndex, 0), safePageCount - 1)
        return "\(safePageIndex + 1)  /  \(safePageCount)"
    }

    static func pdfProgressPercent(pageIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let clampedPage = min(max(pageIndex + 1, 1), pageCount)
        let percent = Int(round(Double(clampedPage) / Double(pageCount) * 100))
        return min(100, max(1, percent))
    }

    static func webProgressPercent(_ progress: Double) -> Int {
        min(100, max(0, Int(round(min(1, max(0, progress)) * 100))))
    }

    static func searchResultText(resultIndex: Int?, resultCount: Int, isSearching: Bool) -> String {
        let safeCount = max(0, resultCount)
        if isSearching {
            let current = resultIndex.map { min(max($0 + 1, 1), max(1, safeCount)) } ?? 0
            return "\(current) / …"
        }
        guard safeCount > 0, let resultIndex else { return "0 / 0" }
        let current = min(max(resultIndex + 1, 1), safeCount)
        return "\(current) / \(safeCount)"
    }

    static func webSectionProgress(index: Int, locationCount: Int) -> Double {
        guard locationCount > 1 else { return 0 }
        let safeIndex = min(max(index, 0), locationCount - 1)
        return Double(safeIndex) / Double(locationCount - 1)
    }
}
