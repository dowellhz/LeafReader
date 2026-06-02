import Cocoa
import PDFKit

extension ReaderWindowController {
    func persistSelectedWordIfNeeded(_ selection: PDFSelection?, text: String, context: String? = nil) -> WordQuestionStartResult? {
        guard shouldPersistHighlight(for: text),
              let selection,
              let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }

        let rawBounds = selection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: rawBounds,
            queryText: text
        ) ?? rawBounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            clearPDFSelectionState()
            pdfView.clearSelection()
            return WordQuestionStartResult(linkID: existing.id, selectedContext: nil)
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let context = vocabularyContextForCurrentSelection(selectedText: text, precomputedContext: context)
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
            clearPDFSelectionState()
            pdfView.clearSelection()
            return WordQuestionStartResult(linkID: record.id, selectedContext: context)
        }

        let id = UUID().uuidString
        let context = vocabularyContextForCurrentSelection(selectedText: text, precomputedContext: context)
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: context,
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            createdAt: Date()
        )
        backfillDictionaryMetadataAsync(linkID: id, word: text)
        addPendingWordAnnotation(id: id, pageIndex: pageIndex, bounds: bounds, word: text)
        clearPDFSelectionState()
        pdfView.clearSelection()
        return WordQuestionStartResult(linkID: id, selectedContext: context)
    }

    func persistSelectedWebWordIfNeeded(text: String, context precomputedContext: String? = nil) -> WordQuestionStartResult? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = sanitizedVocabularyContext(precomputedContext ?? currentWebSelectionContext)
        if let pending = existingPendingWebWordRecord(
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: pending.id)
            return WordQuestionStartResult(linkID: pending.id, selectedContext: nil)
        }
        if let existing = webWordRecordStore?.existingRecord(
            in: storedWebWordRecords,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: existing.id)
            return WordQuestionStartResult(linkID: existing.id, selectedContext: nil)
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
            return WordQuestionStartResult(linkID: record.id, selectedContext: context)
        }

        let id = UUID().uuidString
        markCurrentWebSelectionAsStoredWord(id: id)
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress,
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            createdAt: Date()
        )
        backfillDictionaryMetadataAsync(linkID: id, word: word)
        return WordQuestionStartResult(linkID: id, selectedContext: context)
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

    private func vocabularyContextForCurrentSelection(selectedText: String, precomputedContext: String? = nil) -> String {
        sanitizedVocabularyContext(precomputedContext ?? contextForCurrentSelection(selectedText: selectedText))
    }

    private func sanitizedVocabularyContext(_ context: String) -> String {
        ReaderAIContextBuilder.trimLeadingContextQuotes(context)
    }

}
