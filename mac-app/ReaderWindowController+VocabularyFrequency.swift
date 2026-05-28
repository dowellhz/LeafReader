import Foundation

extension ReaderWindowController {
    func backfillVocabularyFrequenciesIfNeeded(
        progress: @escaping (_ word: String, _ current: Int, _ total: Int) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let preferences = vocabularyReviewPreferences else {
            completion()
            return
        }
        let items = pendingVocabularyFrequencyBackfillItems()
        let service = VocabularyFrequencyBackfillService(preferences: preferences)
        service.backfillIfNeeded(items: items, progress: { progressState in
            progress(progressState.word, progressState.current, progressState.total)
        }) { [weak self] result in
            guard let self else { return }
            self.applyVocabularyFrequencies(result.frequenciesByID)
            completion()
        }
    }

    private func pendingVocabularyFrequencyBackfillItems() -> [VocabularyDictionaryBackfillItem] {
        switch currentDocumentKind {
        case .pdf:
            return VocabularyDictionaryMetadataService.pdfFrequencyBackfillItems(storedWordRecords)
        case .epub, .docx:
            return VocabularyDictionaryMetadataService.webFrequencyBackfillItems(storedWebWordRecords)
        }
    }

    private func applyVocabularyFrequencies(_ frequenciesByID: [String: Int]) {
        guard !frequenciesByID.isEmpty else { return }
        let result = updateStoredVocabularyRecords(
            ids: Set(frequenciesByID.keys),
            updatePDF: { record in
                guard let frequency = frequenciesByID[record.id] else { return false }
                record.dictionaryFrequency = frequency
                return true
            },
            updateWeb: { record in
                guard let frequency = frequenciesByID[record.id] else { return false }
                record.dictionaryFrequency = frequency
                return true
            }
        )
        if result.didUpdate {
            currentVocabularyExportRecords = makeCurrentVocabularyExportRecords()
        }
    }
}
