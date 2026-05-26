import Foundation

struct ReadingNote: Codable, Identifiable {
    let id: String
    let documentID: String
    let documentTitle: String
    let documentKind: String
    let quote: String
    var markdown: String
    let locator: Locator
    let createdAt: Date
    var updatedAt: Date

    struct Locator: Codable {
        var pdfFragments: [PDFFragment]?
        var webAnchor: WebAnchor?
    }

    struct PDFFragment: Codable {
        let pageIndex: Int
        let bounds: StoredPDFWordRect
    }

    struct WebAnchor: Codable {
        let selectedText: String
        let context: String
        let occurrenceIndex: Int?
        let scrollProgress: Double
    }
}

extension Sequence where Element == ReadingNote {
    func sortedByCreatedAt() -> [ReadingNote] {
        sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
