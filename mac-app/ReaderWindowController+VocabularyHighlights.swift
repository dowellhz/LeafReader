import Cocoa
import PDFKit

extension ReaderWindowController {
    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        for record in storedWordRecords {
            addStoredWordAnnotation(record)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return }
        let bounds = displayBounds(for: record, page: page)
        let key = pdfWordRecordStore?.recordKey(pageIndex: record.pageIndex, bounds: bounds)
            ?? "\(record.pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: wordUnderlineBounds(for: bounds), forType: .highlight, withProperties: nil)
        annotation.color = vocabularySelectionHighlightColor(for: ReaderTheme.selected)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
    }

    func refreshStoredWordAnnotationAppearance() {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix("leaf-word:") == true {
                page.removeAnnotation(annotation)
            }
        }
        highlightedSelectionKeys.removeAll()
        restoreStoredWordAnnotations()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func vocabularySelectionHighlightColor(for theme: ReaderTheme) -> NSColor {
        theme.aiSourceUnderlineColor
    }

    func wordUnderlineBounds(for bounds: CGRect) -> CGRect {
        let thickness = min(max(bounds.height * 0.08, 2.2), 3.6)
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + max(0, bounds.height * 0.04),
            width: bounds.width,
            height: thickness
        ).insetBy(dx: -0.8, dy: 0)
    }

    func displayBounds(for record: StoredPDFWordRecord, page: PDFPage) -> CGRect {
        precisePDFSelectionBounds(
            page: page,
            originalBounds: record.bounds.cgRect,
            queryText: record.word
        ) ?? record.bounds.cgRect
    }

    func restoreStoredWebWordHighlights(completion: (() -> Void)? = nil) {
        guard currentDocumentKind != .pdf, !storedWebWordRecords.isEmpty else {
            completion?()
            return
        }
        let payload = storedWebWordRecords.map { record -> [String: Any] in
            var item: [String: Any] = [
                "id": record.id,
                "word": record.word,
                "context": record.context
            ]
            if let occurrenceIndex = record.occurrenceIndex {
                item["occurrenceIndex"] = occurrenceIndex
            }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            completion?()
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreWordHighlights(\(json));") { _, _ in
            completion?()
        }
    }

    func markCurrentWebSelectionAsStoredWord(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderMarkSelectionAsWord && window.leafReaderMarkSelectionAsWord(\(jsStringLiteral(id)));")
    }

    func removeWebWordHighlight(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderRemoveWordHighlight && window.leafReaderRemoveWordHighlight(\(jsStringLiteral(id)));")
    }

}
