import Foundation

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
    let answer: String
    let location: String
    let context: String
    let createdAt: Date
    let srs: VocabularySRSState
}
