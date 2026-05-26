import Foundation
import PDFKit

enum VocabularyContextProvider {
    private static let selectionInset = CGSize(width: -120, height: -36)
    private static let fallbackInset = CGSize(width: -80, height: -24)

    static func pdfContext(for record: StoredPDFWordRecord, document: PDFDocument?) -> String {
        if let context = VocabularyExporter.nonEmptyText(record.context) {
            return context
        }
        guard let page = document?.page(at: record.pageIndex) else { return "" }
        let pageText = page.string ?? ""
        let selectedText = VocabularyExporter.trimmed(record.word)
        if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: pageText, radius: 24) {
            return context
        }
        let expandedBounds = record.bounds.cgRect.insetBy(
            dx: selectionInset.width,
            dy: selectionInset.height
        )
        if let nearbyText = page.selection(for: expandedBounds)?.string,
           let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: nearbyText, radius: 24) {
            return context
        }
        let fallbackBounds = record.bounds.cgRect.insetBy(
            dx: fallbackInset.width,
            dy: fallbackInset.height
        )
        return ReaderAIContextBuilder.normalizeWhitespace(page.selection(for: fallbackBounds)?.string ?? "")
    }
}
