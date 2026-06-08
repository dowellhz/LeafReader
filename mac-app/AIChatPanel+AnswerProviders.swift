import Foundation

extension AIChatPanel {
    func cachedVocabularyAnswerProvider() -> AnswerProvider {
        CachedVocabularyAnswerProvider(answerForLinkID: { [weak self] linkID in
            self?.onLinkedWordAnswerAvailable?(linkID)
        })
    }

    func localOnlyAnswerProvider() -> AnswerProvider {
        LocalDictionaryAnswerProvider(dictionaryLookupService: dictionaryLookupService)
    }

    func cachedLocalDictionaryAnswer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard VocabularyTextPolicy.isSingleEnglishWord(request.text),
              let answer = dictionaryLookupService.cachedDictionaryAnswer(for: request.text, context: request.context) else {
            return nil
        }
        return AnswerProviderResult(
            answer: answer.markdown,
            source: .localDictionary,
            dictionaryMetadata: answer.metadata
        )
    }

    func localDictionaryTagSuffix(fallbackMetadata: VocabularyDictionaryMetadata?) -> String? {
        guard let fallbackMetadata else { return nil }
        return VocabularyTagFormatter.suffix(for: fallbackMetadata.tags)
    }
}
