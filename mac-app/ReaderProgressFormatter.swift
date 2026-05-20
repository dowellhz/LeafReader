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
}
