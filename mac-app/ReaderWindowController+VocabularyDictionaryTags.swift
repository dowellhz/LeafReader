import Foundation

extension ReaderWindowController {
    func vocabularyRecordWithDictionaryTags(_ record: VocabularyExportRecord) -> VocabularyExportRecord {
        if record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return record
        }
        guard VocabularyTextPolicy.speakableWord(record.word) != nil,
              let tags = dictionaryTags(for: record.word) else {
            return record
        }
        persistDictionaryTags(tags, for: record)
        return VocabularyExportRecord(
            ids: record.ids,
            word: record.word,
            answer: record.answer,
            dictionaryTags: tags,
            location: record.location,
            context: record.context,
            createdAt: record.createdAt,
            srs: record.srs
        )
    }

    private func persistDictionaryTags(_ tags: String, for record: VocabularyExportRecord) {
        let idSet = Set(record.ids)
        var didUpdatePDF = false
        for index in storedWordRecords.indices where idSet.contains(storedWordRecords[index].id) {
            guard storedWordRecords[index].dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                continue
            }
            storedWordRecords[index].dictionaryTags = tags
            saveStoredWordRecord(storedWordRecords[index])
            didUpdatePDF = true
        }
        if didUpdatePDF {
            saveStoredWordRecords()
        }

        var didUpdateWeb = false
        for index in storedWebWordRecords.indices where idSet.contains(storedWebWordRecords[index].id) {
            guard storedWebWordRecords[index].dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                continue
            }
            storedWebWordRecords[index].dictionaryTags = tags
            saveStoredWebWordRecord(storedWebWordRecords[index])
            didUpdateWeb = true
        }
        if didUpdateWeb {
            saveStoredWebWordRecords()
        }

        for index in currentVocabularyExportRecords.indices
            where !Set(currentVocabularyExportRecords[index].ids).isDisjoint(with: idSet)
                && currentVocabularyExportRecords[index].dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            currentVocabularyExportRecords[index] = VocabularyExportRecord(
                ids: currentVocabularyExportRecords[index].ids,
                word: currentVocabularyExportRecords[index].word,
                answer: currentVocabularyExportRecords[index].answer,
                dictionaryTags: tags,
                location: currentVocabularyExportRecords[index].location,
                context: currentVocabularyExportRecords[index].context,
                createdAt: currentVocabularyExportRecords[index].createdAt,
                srs: currentVocabularyExportRecords[index].srs
            )
        }
    }
}
