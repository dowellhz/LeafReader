import Foundation

struct WebReadableDocument {
    let html: String
    let htmlFileURL: URL?
    let baseURL: URL
    let plainText: String
    let plainTextLoader: (() -> String)?
    let coverImageURL: URL?
    let tocItems: [ReaderTOCItem]
    let diagnostics: [String]
}

struct ReaderTOCItem {
    let title: String
    let href: String
    let level: Int
}

struct HTMLBodyFragment {
    let content: String
    let bodyClasses: String
    let bodyAttributes: String
}

enum WebDocumentLoader {
    static let regexCacheLock = NSLock()
    static var regexCache: [String: NSRegularExpression] = [:]

    static func load(url: URL) throws -> WebReadableDocument {
        switch ReaderDocumentKind.kind(for: url) {
        case .epub:
            return try loadEPUB(url: url)
        case .docx:
            return try loadDOCX(url: url)
        default:
            throw NSError(domain: "LeafReader", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported document type"
            ])
        }
    }

}
