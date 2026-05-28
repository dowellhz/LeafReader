import Foundation

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
    let answer: String
    let dictionaryTags: String?
    let dictionaryFrequency: Int?
    let location: String
    let context: String
    let createdAt: Date
    let srs: VocabularySRSState

    func withDictionaryMetadata(tags: String? = nil, frequency: Int? = nil) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: ids,
            word: word,
            answer: answer,
            dictionaryTags: tags ?? dictionaryTags,
            dictionaryFrequency: frequency ?? dictionaryFrequency,
            location: location,
            context: context,
            createdAt: createdAt,
            srs: srs
        )
    }
}
