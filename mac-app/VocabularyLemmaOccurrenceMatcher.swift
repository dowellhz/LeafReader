import Foundation
import NaturalLanguage

struct VocabularyLemmaOccurrence: Equatable {
    let range: NSRange
    let surface: String
    let groupingKey: String
}

enum VocabularyLemmaOccurrenceMatcher {
    static let maximumMatchesPerPage = 500

    static func matches(in text: String, groupingKeys: Set<String>) -> [VocabularyLemmaOccurrence] {
        guard !text.isEmpty, !groupingKeys.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.tokenType, .lemma, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: range)

        var occurrences: [VocabularyLemmaOccurrence] = []
        occurrences.reserveCapacity(min(groupingKeys.count * 8, maximumMatchesPerPage))
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .tokenType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { _, tokenRange in
            let surface = String(text[tokenRange])
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                ?? surface
            guard let lexicalClass = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass
            ).0?.rawValue else {
                return true
            }
            let identity = VocabularyLemmaResolver.identity(
                forTaggedSurface: surface,
                lemma: lemma,
                lexicalClass: lexicalClass
            )
            guard groupingKeys.contains(identity.groupingKey) else { return true }
            occurrences.append(VocabularyLemmaOccurrence(
                range: NSRange(tokenRange, in: text),
                surface: surface,
                groupingKey: identity.groupingKey
            ))
            return occurrences.count < maximumMatchesPerPage
        }
        return occurrences
    }
}
