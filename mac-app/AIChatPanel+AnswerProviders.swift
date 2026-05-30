import Foundation

extension AIChatPanel {
    func cachedVocabularyAnswerProvider() -> AnswerProvider {
        CachedVocabularyAnswerProvider(answerForLinkID: { [weak self] linkID in
            self?.onLinkedWordAnswerAvailable?(linkID)
        })
    }

    func cachedOrLocalAnswerProvider() -> AnswerProvider {
        CompositeAnswerProvider(providers: [
            cachedVocabularyAnswerProvider(),
            localOnlyAnswerProvider()
        ])
    }

    func localOnlyAnswerProvider() -> AnswerProvider {
        LocalDictionaryAnswerProvider(dictionaryLookupService: dictionaryLookupService)
    }

    func localDictionaryTagSuffix(for word: String) -> String? {
        LocalDictionaryTagFormatter.suffix(for: dictionaryLookupService.metadata(for: word).tags)
    }
}
