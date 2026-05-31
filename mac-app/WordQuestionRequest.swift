import Foundation

struct WordQuestionRequest {
    let text: String
    let selectedContext: String?
}

struct WordQuestionStartResult {
    let linkID: String?
    let selectedContext: String?
}
