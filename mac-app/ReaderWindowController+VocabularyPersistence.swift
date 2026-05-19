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
            return existing.id
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let record = StoredPDFWordRecord(
                id: UUID().uuidString,
                word: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageIndex: pageIndex,
                bounds: StoredPDFWordRect(bounds),
                context: contextForCurrentSelection(selectedText: text),
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            return record.id
        }

        let id = UUID().uuidString
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: contextForCurrentSelection(selectedText: text),
            createdAt: Date()
        )
        return id
    }

    func persistSelectedWebWordIfNeeded(text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = currentWebSelectionContext.trimmingCharacters(in: .whitespacesAndNewlines)
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
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress,
            createdAt: Date()
        )
        return id
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

}
