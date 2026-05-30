import Cocoa
import PDFKit

extension ReaderWindowController {
    func persistSelectedWordIfNeeded(_ selection: PDFSelection?, text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              let selection,
              let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }

        let selectionBounds = selection.bounds(for: page)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: selectionBounds,
            queryText: text
        ) ?? selectionBounds.insetBy(dx: -1.5, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            pdfView.clearSelection()
            return existing.id
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let context = vocabularyContextForCurrentSelection(selectedText: text)
            let record = StoredPDFWordRecord(
                id: UUID().uuidString,
                word: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageIndex: pageIndex,
                bounds: StoredPDFWordRect(bounds),
                context: context,
                question: reusable.question,
                answer: reusable.answer,
                dictionaryTags: reusable.dictionaryTags,
                dictionaryFrequency: reusable.dictionaryFrequency,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            pdfView.clearSelection()
            return record.id
        }

        let id = UUID().uuidString
        let metadata = dictionaryMetadata(for: text)
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: vocabularyContextForCurrentSelection(selectedText: text),
            dictionaryTags: metadata.tags,
            dictionaryFrequency: metadata.frequency,
            createdAt: Date()
        )
        addPendingWordAnnotation(id: id, pageIndex: pageIndex, bounds: bounds, word: text)
        pdfView.clearSelection()
        return id
    }

    func persistSelectedWebWordIfNeeded(text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = sanitizedVocabularyContext(currentWebSelectionContext)
        if let pending = existingPendingWebWordRecord(
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: pending.id)
            return pending.id
        }
        if let existing = webWordRecordStore?.existingRecord(
            in: storedWebWordRecords,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: existing.id)
            return existing.id
        }
        if let reusable = reusableWebWordRecord(for: word) {
            let id = UUID().uuidString
            let record = StoredWebWordRecord(
                id: id,
                word: word,
                context: context,
                occurrenceIndex: currentWebSelectionOccurrenceIndex,
                scrollProgress: webScrollProgress,
                question: reusable.question,
                answer: reusable.answer,
                dictionaryTags: reusable.dictionaryTags,
                dictionaryFrequency: reusable.dictionaryFrequency,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWebWordRecords.append(record)
            markCurrentWebSelectionAsStoredWord(id: id)
            saveStoredWebWordRecord(record)
            return record.id
        }

        let id = UUID().uuidString
        markCurrentWebSelectionAsStoredWord(id: id)
        let metadata = dictionaryMetadata(for: word)
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress,
            dictionaryTags: metadata.tags,
            dictionaryFrequency: metadata.frequency,
            createdAt: Date()
        )
        return id
    }

    func dictionaryMetadata(for word: String) -> (tags: String?, frequency: Int?) {
        let metadata = VocabularyDictionaryMetadataService.metadata(for: word)
        return (metadata.tags, metadata.frequency)
    }

    func dictionaryTags(for word: String) -> String? {
        dictionaryMetadata(for: word).tags
    }

    func existingPendingWebWordRecord(word: String, context: String, occurrenceIndex: Int?) -> PendingWebWordRecord? {
        let normalizedWord = normalizedWebRecordText(word)
        let normalizedContext = normalizedWebRecordText(context)
        return pendingWebWordRecords.values.first { pending in
            normalizedWebRecordText(pending.word) == normalizedWord
                && normalizedWebRecordText(pending.context) == normalizedContext
                && (pending.occurrenceIndex == occurrenceIndex || pending.occurrenceIndex == nil || occurrenceIndex == nil)
        }
    }

    private func normalizedWebRecordText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func vocabularyContextForCurrentSelection(selectedText: String) -> String {
        sanitizedVocabularyContext(contextForCurrentSelection(selectedText: selectedText))
    }

    private func sanitizedVocabularyContext(_ context: String) -> String {
        ReaderAIContextBuilder.trimLeadingContextQuotes(context)
    }

}
