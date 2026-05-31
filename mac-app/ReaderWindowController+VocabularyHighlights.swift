import Cocoa
import PDFKit

extension ReaderWindowController {
    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        removeAllVocabularyWordAnnotations()
        highlightedSelectionKeys.removeAll()
        for record in storedWordRecords {
            addPDFVocabularyAnnotation(
                id: record.id,
                pageIndex: record.pageIndex,
                storedBounds: record.bounds.cgRect,
                word: record.word,
                refineBounds: true
            )
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        addPDFVocabularyAnnotation(
            id: record.id,
            pageIndex: record.pageIndex,
            storedBounds: record.bounds.cgRect,
            word: record.word,
            refineBounds: false
        )
    }

    func addPendingWordAnnotation(id: String, pageIndex: Int, bounds: CGRect, word: String) {
        addPDFVocabularyAnnotation(id: id, pageIndex: pageIndex, storedBounds: bounds, word: word, refineBounds: false)
    }

    func discardPendingWordAnnotations() {
        restoreStoredWordAnnotations()
    }

    private func addPDFVocabularyAnnotation(
        id: String,
        pageIndex: Int,
        storedBounds: CGRect,
        word: String,
        refineBounds: Bool
    ) {
        guard let page = pdfView.document?.page(at: pageIndex) else { return }
        let bounds = refineBounds ? displayBounds(bounds: storedBounds, word: word, page: page) : storedBounds
        let key = wordAnnotationKey(pageIndex: pageIndex, bounds: bounds)
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: wordUnderlineBounds(for: bounds), forType: .highlight, withProperties: nil)
        annotation.color = vocabularySelectionHighlightColor(for: ReaderTheme.selected)
        annotation.contents = "leaf-word:\(id)"
        page.addAnnotation(annotation)
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func removeAllVocabularyWordAnnotations() {
        guard let document = pdfView.document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix("leaf-word:") == true {
                page.removeAnnotation(annotation)
            }
        }
    }

    private func wordAnnotationKey(pageIndex: Int, bounds: CGRect) -> String {
        pdfWordRecordStore?.recordKey(pageIndex: pageIndex, bounds: bounds)
            ?? "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
    }

    private func displayBounds(bounds storedBounds: CGRect, word: String, page: PDFPage) -> CGRect {
        precisePDFSelectionBounds(
            page: page,
            originalBounds: storedBounds,
            queryText: word
        ) ?? storedBounds
    }

    func displayBounds(for record: StoredPDFWordRecord, page: PDFPage) -> CGRect {
        displayBounds(bounds: record.bounds.cgRect, word: record.word, page: page)
    }

    func refreshStoredWordAnnotationAppearance() {
        restoreStoredWordAnnotations()
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
