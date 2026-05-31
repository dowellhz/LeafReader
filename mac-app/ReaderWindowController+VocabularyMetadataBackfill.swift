import Foundation

extension ReaderWindowController {
    func backfillDictionaryMetadataAsync(linkID: String, word: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let metadata = VocabularyDictionaryMetadataService.metadata(for: trimmedWord)
            guard metadata.tags != nil || metadata.frequency != nil else { return }
            DispatchQueue.main.async {
                self?.applyDictionaryMetadata(metadata, linkID: linkID)
            }
        }
    }

    private func applyDictionaryMetadata(_ metadata: VocabularyDictionaryMetadata, linkID: String) {
        var didUpdate = false

        if var pending = pendingPDFWordRecords[linkID] {
            if applyMetadata(metadata, tags: &pending.dictionaryTags, frequency: &pending.dictionaryFrequency) {
                pendingPDFWordRecords[linkID] = pending
                didUpdate = true
            }
        }

        if var pending = pendingWebWordRecords[linkID] {
            if applyMetadata(metadata, tags: &pending.dictionaryTags, frequency: &pending.dictionaryFrequency) {
                pendingWebWordRecords[linkID] = pending
                didUpdate = true
            }
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            var record = storedWordRecords[index]
            if applyMetadata(metadata, tags: &record.dictionaryTags, frequency: &record.dictionaryFrequency) {
                storedWordRecords[index] = record
                saveStoredWordRecord(record)
                didUpdate = true
            }
        }

        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            var record = storedWebWordRecords[index]
            if applyMetadata(metadata, tags: &record.dictionaryTags, frequency: &record.dictionaryFrequency) {
                storedWebWordRecords[index] = record
                saveStoredWebWordRecord(record)
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        updateCurrentVocabularyExportMetadata(metadata, linkID: linkID)
    }

    private func applyMetadata(
        _ metadata: VocabularyDictionaryMetadata,
        tags: inout String?,
        frequency: inout Int?
    ) -> Bool {
        var didUpdate = false
        if tags == nil, let metadataTags = metadata.tags {
            tags = metadataTags
            didUpdate = true
        }
        if frequency == nil, let metadataFrequency = metadata.frequency {
            frequency = metadataFrequency
            didUpdate = true
        }
        return didUpdate
    }

    private func updateCurrentVocabularyExportMetadata(_ metadata: VocabularyDictionaryMetadata, linkID: String) {
        for index in currentVocabularyExportRecords.indices where currentVocabularyExportRecords[index].ids.contains(linkID) {
            currentVocabularyExportRecords[index] = currentVocabularyExportRecords[index].withDictionaryMetadata(
                tags: metadata.tags,
                frequency: metadata.frequency
            )
        }
    }
}
