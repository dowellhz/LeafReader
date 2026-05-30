import Foundation

struct AnswerProviderRequest {
    let text: String
    let context: String
    let linkID: String?
}

struct AnswerProviderResult: Equatable {
    enum Source: Equatable {
        case cachedVocabulary
        case localDictionary
    }

    let answer: String
    let source: Source
}

protocol AnswerProvider {
    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult?
}

struct CachedVocabularyAnswerProvider: AnswerProvider {
    let answerForLinkID: (String) -> String?

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard let linkID = request.linkID,
              let answer = answerForLinkID(linkID)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !answer.isEmpty else {
            return nil
        }
        return AnswerProviderResult(answer: answer, source: .cachedVocabulary)
    }
}

struct LocalDictionaryAnswerProvider: AnswerProvider {
    let dictionaryLookupService: DictionaryLookupService
    let isDictionaryInstalled: () -> Bool

    init(
        dictionaryLookupService: DictionaryLookupService = LocalDictionaryLookupService.shared,
        isDictionaryInstalled: @escaping () -> Bool = { ECDICTDictionary.shared.isInstalled }
    ) {
        self.dictionaryLookupService = dictionaryLookupService
        self.isDictionaryInstalled = isDictionaryInstalled
    }

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        if let answer = dictionaryLookupService.markdownAnswer(for: request.text, context: request.context) {
            return AnswerProviderResult(answer: answer, source: .localDictionary)
        }
        guard isDictionaryInstalled() else { return nil }
        let word = ECDICTDictionary.lookupKey(request.text)
        let visibleWord = word.isEmpty
            ? request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : word
        return AnswerProviderResult(
            answer: AppText.localized(
                "本地 ECDICT 词典未收录：\(visibleWord)",
                "The local ECDICT dictionary has no entry for: \(visibleWord)"
            ),
            source: .localDictionary
        )
    }
}

struct CompositeAnswerProvider: AnswerProvider {
    let providers: [AnswerProvider]

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        for provider in providers {
            if let answer = provider.answer(for: request) {
                return answer
            }
        }
        return nil
    }
}

enum LocalDictionaryTagFormatter {
    static func suffix(for tags: String?) -> String? {
        let values = tagValues(from: tags)
        guard !values.isEmpty else { return nil }
        let renderedTags = values.map { "`\($0.uppercased())`" }.joined(separator: " ")
        return "\n\n\(AppText.localized("本地词典 Tags：", "Local dictionary tags:")) \(renderedTags)"
    }

    static func appendSuffix(to answer: String, suffix: String?) -> String {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suffix,
              !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedAnswer
        }
        return trimmedAnswer + suffix
    }

    private static func tagValues(from tags: String?) -> [String] {
        String(tags ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",;/| ").union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
