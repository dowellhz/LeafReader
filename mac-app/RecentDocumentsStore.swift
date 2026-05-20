import Foundation

struct RecentDocumentItem: Codable {
    let path: String
    let title: String
    let kind: String
    let openedAt: Date
    let readingProgress: Double?
}

enum RecentDocumentsStore {
    private static let defaultsKey = "recentDocuments"
    private static let limit = 200

    static func record(url: URL, kind: ReaderDocumentKind) {
        var items = load()
        let fileURL = url.standardizedFileURL
        let path = fileURL.path
        items.removeAll { $0.path == path }
        items.insert(
            RecentDocumentItem(
                path: path,
                title: fileURL.deletingPathExtension().lastPathComponent,
                kind: kind.displayName,
                openedAt: Date(),
                readingProgress: nil
            ),
            at: 0
        )
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save(items)
    }

    @discardableResult
    static func record(urls: [URL]) -> [String] {
        var items = load()
        var existingItemsByPath: [String: RecentDocumentItem] = [:]
        for item in items where existingItemsByPath[item.path] == nil {
            existingItemsByPath[item.path] = item
        }
        var frontItems: [RecentDocumentItem] = []
        for url in supportedUniqueURLs(urls) {
            guard let kind = ReaderDocumentKind.kind(for: url) else { continue }
            let fileURL = url.standardizedFileURL
            let path = fileURL.path
            if let existing = existingItemsByPath[path] {
                frontItems.append(existing)
            } else {
                let item = RecentDocumentItem(
                    path: path,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    kind: kind.displayName,
                    openedAt: .distantPast,
                    readingProgress: nil
                )
                frontItems.append(item)
                items.append(item)
            }
        }
        guard !frontItems.isEmpty else { return [] }
        if items.count > limit {
            let importedPaths = Set(frontItems.map(\.path))
            let importedItems = items.filter { importedPaths.contains($0.path) }
            let remainingItems = items
                .filter { !importedPaths.contains($0.path) }
                .sorted { $0.openedAt > $1.openedAt }
            let remainingLimit = max(0, limit - importedItems.count)
            items = Array(remainingItems.prefix(remainingLimit)) + Array(importedItems.prefix(limit))
        }
        save(items)
        return frontItems.map(\.path)
    }

    static func supportedUniqueURLs(_ urls: [URL]) -> [URL] {
        var results: [URL] = []
        var seenPaths = Set<String>()
        for url in urls where ReaderDocumentKind.kind(for: url) != nil {
            let fileURL = url.standardizedFileURL
            guard !seenPaths.contains(fileURL.path) else { continue }
            seenPaths.insert(fileURL.path)
            results.append(fileURL)
        }
        return results
    }

    static func load() -> [RecentDocumentItem] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }
        let items: [RecentDocumentItem]
        do {
            items = try JSONDecoder().decode([RecentDocumentItem].self, from: data)
        } catch {
            NSLog("LeafReader recent documents: failed to decode store (error=%@)", error.localizedDescription)
            return []
        }
        return items.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func remove(path: String) {
        var items = load()
        items.removeAll { $0.path == path }
        save(items)
    }

    static func updateProgress(url: URL, kind: ReaderDocumentKind, progress: Double) {
        var items = load()
        let fileURL = url.standardizedFileURL
        let path = fileURL.path
        let normalizedProgress = min(max(progress, 0), 1)
        if let index = items.firstIndex(where: { $0.path == path }) {
            let existing = items[index]
            items[index] = RecentDocumentItem(
                path: existing.path,
                title: existing.title,
                kind: existing.kind,
                openedAt: existing.openedAt,
                readingProgress: normalizedProgress
            )
        } else {
            items.insert(
                RecentDocumentItem(
                    path: path,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    kind: kind.displayName,
                    openedAt: Date(),
                    readingProgress: normalizedProgress
                ),
                at: 0
            )
            if items.count > limit {
                items = Array(items.prefix(limit))
            }
        }
        save(items)
    }

    private static func save(_ items: [RecentDocumentItem]) {
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            NSLog("LeafReader recent documents: failed to encode store (count=%d, error=%@)", items.count, error.localizedDescription)
            return
        }
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
