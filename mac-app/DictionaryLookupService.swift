import Foundation

struct VocabularyDictionaryMetadata: Equatable {
    let tags: String?
    let frequency: Int?
}

struct VocabularyDictionaryAnswer {
    let markdown: String
    let metadata: VocabularyDictionaryMetadata
}

protocol DictionaryLookupService {
    func lookup(_ query: String) -> ECDICTEntry?
    func markdownAnswer(for query: String, context: String) -> String?
    func dictionaryAnswer(for query: String, context: String) -> VocabularyDictionaryAnswer?
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

    func dictionaryAnswer(for query: String, context: String = "") -> VocabularyDictionaryAnswer? {
        guard let entry = lookup(query) else { return nil }
        return VocabularyDictionaryAnswer(
            markdown: ECDICTAnswerFormatter.markdownAnswer(for: entry, context: context),
            metadata: metadata(for: entry)
        )
    }

    func metadata(for word: String) -> VocabularyDictionaryMetadata {
        guard let entry = lookup(word) else {
            return VocabularyDictionaryMetadata(tags: nil, frequency: nil)
        }
        return metadata(for: entry)
    }

    private func metadata(for entry: ECDICTEntry) -> VocabularyDictionaryMetadata {
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
