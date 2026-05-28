import Foundation

enum VocabularyReviewDisplayRecordLoader {
    static func displayRecord(
        for record: VocabularyExportRecord,
        metadataLookup: (String) -> (tags: String?, frequency: Int?),
        persistTags: (String, VocabularyExportRecord) -> Void
    ) -> VocabularyExportRecord {
        if record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return record
        }
        guard VocabularyTextPolicy.speakableWord(record.word) != nil else {
            return record
        }
        let metadata = metadataLookup(record.word)
        guard let tags = metadata.tags?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tags.isEmpty else {
            return record
        }
        persistTags(tags, record)
        return record.withDictionaryMetadata(tags: tags)
    }
}
