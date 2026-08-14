import Cocoa
import PDFKit

private struct VocabularyFormHighlightTarget {
    let linkID: String
    let primarySurface: String
}

private struct VocabularyFormPageMatch {
    let pageIndex: Int
    let occurrence: VocabularyLemmaOccurrence
}

extension ReaderWindowController {
    var showsRelatedWordForms: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.showsRelatedWordFormsDefaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.showsRelatedWordFormsDefaultsKey)
        }
    }

    @objc func toggleRelatedWordForms(_ sender: NSButton) {
        showsRelatedWordForms.toggle()
        updateRelatedFormsButton()
        restoreStoredWordAnnotations()
    }

    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        vocabularyState.pdfAnnotationRestoreGeneration += 1
        removeAllVocabularyWordAnnotations()
        highlightedSelectionKeys.removeAll()
        materializeStoredWordAnnotationsForVisiblePages()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        let didAdd = addPDFVocabularyAnnotation(
            record,
            isPrimaryForm: primaryVocabularyFormRecordIDs().contains(record.id),
            refineBounds: true,
            invalidateDisplay: true
        )
        if didAdd {
            scheduleVocabularyFormAnnotationsForVisiblePages()
        }
    }

    func addPendingWordAnnotation(id: String, pageIndex: Int, bounds: CGRect, word: String) {
        _ = addPDFVocabularyAnnotation(
            id: id,
            pageIndex: pageIndex,
            storedBounds: bounds,
            word: word,
            textAnchor: pendingPDFWordRecords[id]?.textAnchor,
            isPrimaryForm: true,
            refineBounds: true,
            invalidateDisplay: true
        )
    }

    func discardPendingWordAnnotations() {
        restoreStoredWordAnnotations()
    }

    func materializeStoredWordAnnotationsForVisiblePages() {
        let visiblePageIndexes = visiblePDFPageIndexes()
        let indexes = PDFVocabularyHighlightPolicy.visibleRecordIndexes(
            pageIndexes: storedWordRecords.map(\.pageIndex),
            visiblePageIndexes: visiblePageIndexes
        )
        guard !indexes.isEmpty else {
            scheduleVocabularyFormAnnotationsForVisiblePages()
            return
        }
        materializeStoredWordAnnotationBatch(
            recordIndexes: indexes,
            primaryFormRecordIDs: primaryVocabularyFormRecordIDs(),
            startIndex: 0,
            generation: vocabularyState.pdfAnnotationRestoreGeneration,
            documentID: currentFileMD5
        )
    }

    private func materializeStoredWordAnnotationBatch(
        recordIndexes: [Int],
        primaryFormRecordIDs: Set<String>,
        startIndex: Int,
        generation: Int,
        documentID: String?
    ) {
        guard generation == vocabularyState.pdfAnnotationRestoreGeneration,
              currentDocumentKind == .pdf,
              currentFileMD5 == documentID,
              let batchRange = PDFVocabularyHighlightPolicy.batchRange(
                startIndex: startIndex,
                count: recordIndexes.count
              ) else {
            return
        }

        let visiblePageIndexes = visiblePDFPageIndexes()
        var didAddAnnotation = false
        for batchIndex in batchRange {
            let recordIndex = recordIndexes[batchIndex]
            guard storedWordRecords.indices.contains(recordIndex) else { continue }
            let record = storedWordRecords[recordIndex]
            guard visiblePageIndexes.contains(record.pageIndex) else { continue }
            didAddAnnotation = addPDFVocabularyAnnotation(
                record,
                isPrimaryForm: primaryFormRecordIDs.contains(record.id),
                refineBounds: true,
                invalidateDisplay: false
            ) || didAddAnnotation
        }
        if didAddAnnotation {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }

        let nextIndex = batchRange.upperBound
        guard nextIndex < recordIndexes.count else {
            scheduleVocabularyFormAnnotationsForVisiblePages()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.materializeStoredWordAnnotationBatch(
                recordIndexes: recordIndexes,
                primaryFormRecordIDs: primaryFormRecordIDs,
                startIndex: nextIndex,
                generation: generation,
                documentID: documentID
            )
        }
    }

    @discardableResult
    private func addPDFVocabularyAnnotation(
        _ record: StoredPDFWordRecord,
        isPrimaryForm: Bool,
        refineBounds: Bool,
        invalidateDisplay: Bool
    ) -> Bool {
        addPDFVocabularyAnnotation(
            id: record.id,
            pageIndex: record.pageIndex,
            storedBounds: record.bounds.cgRect,
            word: record.word,
            textAnchor: record.textAnchor,
            isPrimaryForm: isPrimaryForm,
            refineBounds: refineBounds,
            invalidateDisplay: invalidateDisplay
        )
    }

    @discardableResult
    private func addPDFVocabularyAnnotation(
        id: String,
        pageIndex: Int,
        storedBounds: CGRect,
        word: String,
        textAnchor: TextQuoteAnchor?,
        isPrimaryForm: Bool,
        refineBounds: Bool,
        invalidateDisplay: Bool
    ) -> Bool {
        guard isPrimaryForm || showsRelatedWordForms,
              let page = pdfView.document?.page(at: pageIndex) else { return false }
        let bounds = refineBounds
            ? displayBounds(
                id: id,
                pageIndex: pageIndex,
                storedBounds: storedBounds,
                word: word,
                textAnchor: textAnchor,
                page: page
            )
            : storedBounds
        let key = wordAnnotationKey(pageIndex: pageIndex, bounds: bounds)
        guard !highlightedSelectionKeys.contains(key) else { return false }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: wordUnderlineBounds(for: bounds), forType: .highlight, withProperties: nil)
        annotation.color = isPrimaryForm
            ? vocabularySelectionHighlightColor(for: ReaderTheme.selected)
            : vocabularyRelatedFormHighlightColor(for: ReaderTheme.selected)
        annotation.contents = "leaf-word:\(id)"
        page.addAnnotation(annotation)
        vocabularyState.renderedPDFWordAnnotations.append((page, annotation))
        if invalidateDisplay {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }
        return true
    }

    func removeAllVocabularyWordAnnotations() {
        for rendered in vocabularyState.renderedPDFWordAnnotations {
            rendered.page.removeAnnotation(rendered.annotation)
        }
        vocabularyState.renderedPDFWordAnnotations.removeAll()
    }

    private func visiblePDFPageIndexes() -> Set<Int> {
        guard let document = pdfView.document else { return [] }
        let visiblePages = pdfView.visiblePages.isEmpty
            ? [pdfView.currentPage].compactMap { $0 }
            : pdfView.visiblePages
        return Set(visiblePages.compactMap { page in
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        })
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
        displayBounds(
            id: record.id,
            pageIndex: record.pageIndex,
            storedBounds: record.bounds.cgRect,
            word: record.word,
            textAnchor: record.textAnchor,
            page: page
        )
    }

    private func displayBounds(
        id: String,
        pageIndex: Int,
        storedBounds: CGRect,
        word: String,
        textAnchor: TextQuoteAnchor?,
        page: PDFPage
    ) -> CGRect {
        if let cached = vocabularyState.resolvedPDFWordBounds[id] {
            return cached
        }

        let sourceText = pdfTextSnapshot?.pageText(at: pageIndex) ?? page.string
        let resolved: CGRect
        if let textAnchor,
           textAnchor.unitOrdinal == pageIndex,
           let sourceText,
           let range = textAnchor.resolvedRange(in: sourceText),
           let selection = page.selection(for: range),
           let exactBounds = exactPDFSelectionBounds(selection, page: page) {
            resolved = exactBounds
        } else {
            resolved = displayBounds(bounds: storedBounds, word: word, page: page)
        }
        vocabularyState.resolvedPDFWordBounds[id] = resolved
        return resolved
    }

    func refreshStoredWordAnnotationAppearance() {
        restoreStoredWordAnnotations()
    }

    func vocabularySelectionHighlightColor(for theme: ReaderTheme) -> NSColor {
        theme.aiSourceUnderlineColor
    }

    func vocabularyRelatedFormHighlightColor(for theme: ReaderTheme) -> NSColor {
        let base = vocabularySelectionHighlightColor(for: theme)
        return base.withAlphaComponent(base.alphaComponent * 0.42)
    }

    private func primaryVocabularyFormRecordIDs() -> Set<String> {
        VocabularyRelatedFormPolicy.primarySampleIDs(storedWordRecords.map { record in
            VocabularyWordSample(
                id: record.id,
                word: record.word,
                context: record.context,
                createdAt: record.createdAt
            )
        })
    }

    private func vocabularyFormHighlightTargets() -> [String: VocabularyFormHighlightTarget] {
        let primaryIDs = primaryVocabularyFormRecordIDs()
        var targets: [String: VocabularyFormHighlightTarget] = [:]
        for record in storedWordRecords.sorted(by: { $0.createdAt < $1.createdAt }) where primaryIDs.contains(record.id) {
            let identity = VocabularyLemmaResolver.identity(for: record.word, context: record.context)
            guard identity.groupingKey.hasPrefix("lemma:") else { continue }
            if targets[identity.groupingKey] == nil {
                targets[identity.groupingKey] = VocabularyFormHighlightTarget(
                    linkID: record.id,
                    primarySurface: identity.surface
                )
            }
        }
        return targets
    }

    private func scheduleVocabularyFormAnnotationsForVisiblePages() {
        guard currentDocumentKind == .pdf,
              let snapshot = pdfTextSnapshot else { return }
        let targets = vocabularyFormHighlightTargets()
        guard !targets.isEmpty else { return }
        let visiblePageIndexes = visiblePDFPageIndexes().sorted()
        guard !visiblePageIndexes.isEmpty else { return }

        let annotationGeneration = vocabularyState.pdfAnnotationRestoreGeneration
        let snapshotGeneration = pdfTextSnapshotGeneration
        let documentID = currentFileMD5
        let groupingKeys = Set(targets.keys)
        let pageTexts = visiblePageIndexes.compactMap { pageIndex -> (Int, String)? in
            guard let text = snapshot.pageText(at: pageIndex), !text.isEmpty else { return nil }
            return (pageIndex, text)
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let matches = pageTexts.flatMap { pageIndex, text in
                VocabularyLemmaOccurrenceMatcher.matches(
                    in: text,
                    groupingKeys: groupingKeys
                ).map { VocabularyFormPageMatch(pageIndex: pageIndex, occurrence: $0) }
            }
            DispatchQueue.main.async {
                guard let self,
                      self.currentDocumentKind == .pdf,
                      self.currentFileMD5 == documentID,
                      self.pdfTextSnapshotGeneration == snapshotGeneration,
                      self.vocabularyState.pdfAnnotationRestoreGeneration == annotationGeneration else {
                    return
                }
                self.materializeVocabularyFormAnnotations(matches, targets: targets)
            }
        }
    }

    private func materializeVocabularyFormAnnotations(
        _ matches: [VocabularyFormPageMatch],
        targets: [String: VocabularyFormHighlightTarget]
    ) {
        var didAddAnnotation = false
        for match in matches {
            guard let target = targets[match.occurrence.groupingKey],
                  let page = pdfView.document?.page(at: match.pageIndex),
                  let selection = page.selection(for: match.occurrence.range) else {
                continue
            }
            let bounds = exactPDFSelectionBounds(selection, page: page)
                ?? selection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let isPrimaryForm = match.occurrence.surface.caseInsensitiveCompare(target.primarySurface) == .orderedSame
            didAddAnnotation = addPDFVocabularyAnnotation(
                id: target.linkID,
                pageIndex: match.pageIndex,
                storedBounds: bounds,
                word: match.occurrence.surface,
                textAnchor: nil,
                isPrimaryForm: isPrimaryForm,
                refineBounds: false,
                invalidateDisplay: false
            ) || didAddAnnotation
        }
        if didAddAnnotation {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }
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
