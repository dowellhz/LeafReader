import Foundation

extension ReaderWindowController {
    func vocabularyRecordWithDictionaryMetadata(_ record: VocabularyExportRecord) -> VocabularyExportRecord {
        VocabularyReviewDisplayRecordLoader.displayRecord(
            for: record,
            metadataLookup: dictionaryMetadata(for:),
            persistTags: persistDictionaryMetadata(tags:for:)
        )
    }

    func persistDictionaryMetadata(tags: String, for record: VocabularyExportRecord) {
        let idSet = Set(record.ids)
        updateStoredVocabularyRecords(
            ids: idSet,
            updatePDF: { record in
                guard record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                    return false
                }
                record.dictionaryTags = tags
                return true
            },
            updateWeb: { record in
                guard record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                    return false
                }
                record.dictionaryTags = tags
                return true
            }
        )

        for index in currentVocabularyExportRecords.indices
            where !Set(currentVocabularyExportRecords[index].ids).isDisjoint(with: idSet)
                && currentVocabularyExportRecords[index].dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            currentVocabularyExportRecords[index] = currentVocabularyExportRecords[index].withDictionaryMetadata(tags: tags)
        }
    }
}
