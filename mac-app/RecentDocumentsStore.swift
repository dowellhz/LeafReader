import Foundation

struct RecentDocumentItem: Codable {
    let path: String
    let title: String
    let kind: String
    let openedAt: Date
}

enum RecentDocumentsStore {
    private static let defaultsKey = "recentDocuments"
    private static let limit = 24

    static func record(url: URL, kind: ReaderDocumentKind) {
        var items = load()
        let path = url.path
        items.removeAll { $0.path == path }
        items.insert(
            RecentDocumentItem(
                path: path,
                title: url.deletingPathExtension().lastPathComponent,
                kind: kind.displayName,
                openedAt: Date()
            ),
            at: 0
        )
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save(items)
    }

    static func load() -> [RecentDocumentItem] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) else {
            return []
        }
        return items.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func save(_ items: [RecentDocumentItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

private extension ReaderDocumentKind {
    var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .epub:
            return "EPUB"
        case .docx:
            return "DOCX"
        }
    }
}
