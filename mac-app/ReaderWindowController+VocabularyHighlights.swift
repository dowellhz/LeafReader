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
        let key = pdfWordRecordStore?.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            ?? "\(record.pageIndex):\(Int(record.bounds.x.rounded())):\(Int(record.bounds.y.rounded())):\(Int(record.bounds.width.rounded())):\(Int(record.bounds.height.rounded()))"
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: record.bounds.cgRect, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
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
