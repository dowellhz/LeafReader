import Foundation

enum VocabularyFilter: Int {
    case due = 0
    case new = 1
    case all = 2
}

enum VocabularyReviewPriority: String {
    case oldWordsFirst
    case newWordsFirst
}
