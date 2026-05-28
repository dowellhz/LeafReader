import Foundation

extension ReaderWindowController {
    func vocabularyAnswerBody(_ answer: String, word: String) -> String {
        VocabularyAnswerFormatter.answerBody(answer, word: word)
    }

    func normalizeVocabularyHeading(_ text: String) -> String {
        VocabularyAnswerFormatter.normalizedHeading(text)
    }
}
