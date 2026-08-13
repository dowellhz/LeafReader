import Foundation

final class DocumentLoadCancellationToken {
    private let lock = NSLock()
    private var isCancelledStorage = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelledStorage
    }

    func cancel() {
        lock.lock()
        isCancelledStorage = true
        lock.unlock()
    }

    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

struct WebReadableDocument {
    let html: String
    let htmlFileURL: URL?
    let baseURL: URL
    let plainText: String
    let plainTextLoader: (() -> String)?
    let coverImageURL: URL?
    let tocItems: [ReaderTOCItem]
    let diagnostics: [String]
    let ownedResource: OwnedTemporaryResource?

    init(
        html: String,
        htmlFileURL: URL?,
        baseURL: URL,
        plainText: String,
        plainTextLoader: (() -> String)?,
        coverImageURL: URL?,
        tocItems: [ReaderTOCItem],
        diagnostics: [String],
        ownedResource: OwnedTemporaryResource? = nil
    ) {
        self.html = html
        self.htmlFileURL = htmlFileURL
        self.baseURL = baseURL
        self.plainText = plainText
        self.plainTextLoader = plainTextLoader
        self.coverImageURL = coverImageURL
        self.tocItems = tocItems
        self.diagnostics = diagnostics
        self.ownedResource = ownedResource
    }
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

    static func load(
        url: URL,
        cancellationToken: DocumentLoadCancellationToken? = nil
    ) throws -> WebReadableDocument {
        switch ReaderDocumentKind.kind(for: url) {
        case .epub:
            try cancellationToken?.checkCancellation()
            return try loadEPUB(url: url)
        case .docx:
            return try loadDOCX(url: url, cancellationToken: cancellationToken)
        default:
            throw NSError(domain: "LeafReader", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported document type"
            ])
        }
    }

}
