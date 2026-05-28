import Foundation

extension ReaderWindowController {
    func vocabularyRecordWithDictionaryMetadata(_ record: VocabularyExportRecord) -> VocabularyExportRecord {
        if record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return record
        }
        guard VocabularyTextPolicy.speakableWord(record.word) != nil,
              let tags = dictionaryTags(for: record.word) else {
            return record
        }
        persistDictionaryMetadata(tags: tags, for: record)
        return record.withDictionaryMetadata(tags: tags)
    }

    private func persistDictionaryMetadata(tags: String, for record: VocabularyExportRecord) {
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
