import Foundation

struct VocabularyDictionaryMetadata {
    let tags: String?
    let frequency: Int?
}

protocol DictionaryLookupService {
    func lookup(_ query: String) -> ECDICTEntry?
    func markdownAnswer(for query: String, context: String) -> String?
    func metadata(for word: String) -> VocabularyDictionaryMetadata
}

final class LocalDictionaryLookupService: DictionaryLookupService {
    static let shared = LocalDictionaryLookupService()

    private let dictionary: ECDICTDictionary

    init(dictionary: ECDICTDictionary = .shared) {
        self.dictionary = dictionary
    }

    func lookup(_ query: String) -> ECDICTEntry? {
        dictionary.lookup(query)
    }

    func markdownAnswer(for query: String, context: String = "") -> String? {
        dictionary.markdownAnswer(for: query, context: context)
    }

    func metadata(for word: String) -> VocabularyDictionaryMetadata {
        guard let entry = lookup(word) else {
            return VocabularyDictionaryMetadata(tags: nil, frequency: nil)
        }
        let tags = entry.tags.trimmingCharacters(in: .whitespacesAndNewlines)
        return VocabularyDictionaryMetadata(
            tags: tags.isEmpty ? nil : tags,
            frequency: Self.frequency(from: entry.frq)
        )
    }

    private static func frequency(from value: String) -> Int? {
        guard let frequency = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), frequency > 0 else {
            return nil
        }
        return frequency
    }
}
