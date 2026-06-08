import Foundation

extension ReaderWindowController {
    func vocabularyAnswerBody(_ answer: String, word: String) -> String {
        VocabularyAnswerFormatter.answerBody(answer, word: word)
    }

}
