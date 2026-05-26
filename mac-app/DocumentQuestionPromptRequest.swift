import Foundation

struct DocumentQuestionPromptRequest {
    let question: String
    let questionSubject: String
    let context: String

    init(question: String, questionSubject: String = "", context: String) {
        self.question = question
        self.questionSubject = questionSubject
        self.context = context
    }
}

typealias DocumentQuestionPromptHandler = (
    _ request: DocumentQuestionPromptRequest,
    _ completion: @escaping (String?) -> Void
) -> Void
