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

        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
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

    func refreshStoredWebWordHighlightsClearingTransientSelection() {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderClearSelectionVisualOnly && window.leafReaderClearSelectionVisualOnly();") { [weak self] _, _ in
            guard let self else { return }
            self.restoreStoredWebWordHighlights { [weak self] in
                guard let self else { return }
                self.restoreWebAISourceUnderlines(for: self.aiPanel.activeConversationSources())
            }
        }
    }
}
