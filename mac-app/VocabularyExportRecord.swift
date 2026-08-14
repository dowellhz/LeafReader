import Foundation

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
    let lemma: String
    let surfaceForms: [String]
    let answer: String
    let dictionaryTags: String?
    let dictionaryFrequency: Int?
    let location: String
    let context: String
    let createdAt: Date
    let srs: VocabularySRSState

    init(
        ids: [String],
        word: String,
        lemma: String? = nil,
        surfaceForms: [String] = [],
        answer: String,
        dictionaryTags: String?,
        dictionaryFrequency: Int?,
        location: String,
        context: String,
        createdAt: Date,
        srs: VocabularySRSState
    ) {
        self.ids = ids
        self.word = word
        self.lemma = lemma ?? VocabularyLemmaResolver.identity(for: word, context: context).lemma
        self.surfaceForms = surfaceForms.isEmpty ? [word] : surfaceForms
        self.answer = answer
        self.dictionaryTags = dictionaryTags
        self.dictionaryFrequency = dictionaryFrequency
        self.location = location
        self.context = context
        self.createdAt = createdAt
        self.srs = srs
    }

    func withDictionaryMetadata(tags: String? = nil, frequency: Int? = nil) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: ids,
            word: word,
            lemma: lemma,
            surfaceForms: surfaceForms,
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
