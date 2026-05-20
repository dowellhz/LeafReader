import Foundation

struct RecentDocumentItem {
    let path: String
    let title: String
    let openedAt: Date
}

private func supportedUniquePaths(_ paths: [String]) -> [String] {
    var results: [String] = []
    var seen = Set<String>()
    for path in paths {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ["pdf", "epub", "docx"].contains(ext), !seen.contains(path) else { continue }
        seen.insert(path)
        results.append(path)
    }
    return results
}

private func importedFrontPaths(existing: [RecentDocumentItem], droppedPaths: [String]) -> [String] {
    var existingItemsByPath: [String: RecentDocumentItem] = [:]
    for item in existing where existingItemsByPath[item.path] == nil {
        existingItemsByPath[item.path] = item
    }
    var frontPaths: [String] = []
    for path in supportedUniquePaths(droppedPaths) {
        if existingItemsByPath[path] != nil {
            frontPaths.append(path)
        } else {
            frontPaths.append(path)
        }
    }
    return frontPaths
}

private func storedPathsAfterImport(existing: [RecentDocumentItem], droppedPaths: [String]) -> [String] {
    var items = existing
    var existingItemsByPath: [String: RecentDocumentItem] = [:]
    for item in items where existingItemsByPath[item.path] == nil {
        existingItemsByPath[item.path] = item
    }
    for path in supportedUniquePaths(droppedPaths) where existingItemsByPath[path] == nil {
        items.append(RecentDocumentItem(
            path: path,
            title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            openedAt: .distantPast
        ))
        existingItemsByPath[path] = items.last
    }
    return items.map(\.path)
}

private enum DroppedDocumentAction: Equatable {
    case none
    case openSingle(String)
    case showShelf(priorityPaths: [String])
}

private func droppedDocumentAction(paths: [String]) -> DroppedDocumentAction {
    let supportedDropCount = paths.filter { ["pdf", "epub", "docx"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
    let supported = supportedUniquePaths(paths)
    if supportedDropCount == 1, supported.count == 1 {
        return .openSingle(supported[0])
    }
    if supportedDropCount > 1, !supported.isEmpty {
        return .showShelf(priorityPaths: supported)
    }
    return .none
}

private func sortedRecentDocuments(_ items: [RecentDocumentItem], priorityPaths: [String]) -> [RecentDocumentItem] {
    guard !priorityPaths.isEmpty else {
        return items.sorted {
            if $0.openedAt != $1.openedAt {
                return $0.openedAt > $1.openedAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var priorityIndex: [String: Int] = [:]
    for (index, path) in priorityPaths.enumerated() where priorityIndex[path] == nil {
        priorityIndex[path] = index
    }
    return items.sorted { lhs, rhs in
        let lhsPriority = priorityIndex[lhs.path]
        let rhsPriority = priorityIndex[rhs.path]
        switch (lhsPriority, rhsPriority) {
        case let (.some(left), .some(right)):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.openedAt != rhs.openedAt {
                return lhs.openedAt > rhs.openedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

enum ReaderShelfLogicTests {
    static func testRecentDocumentSortingAndImport() throws {
        let old = Date(timeIntervalSince1970: 100)
        let mid = Date(timeIntervalSince1970: 200)
        let recent = Date(timeIntervalSince1970: 300)
        let items = [
            RecentDocumentItem(path: "/books/old.pdf", title: "Old", openedAt: old),
            RecentDocumentItem(path: "/books/recent.pdf", title: "Recent", openedAt: recent),
            RecentDocumentItem(path: "/books/mid.pdf", title: "Mid", openedAt: mid)
        ]

        try expectEqual(sortedRecentDocuments(items, priorityPaths: []).map(\.path), ["/books/recent.pdf", "/books/mid.pdf", "/books/old.pdf"], "plain shelf sorting should use recent reading")
        try expectEqual(sortedRecentDocuments(items, priorityPaths: ["/books/old.pdf", "/books/mid.pdf"]).map(\.path), ["/books/old.pdf", "/books/mid.pdf", "/books/recent.pdf"], "open shelf import should prioritize dropped paths")

        let frontPaths = importedFrontPaths(existing: items, droppedPaths: ["/books/old.pdf", "/books/new.epub", "/books/old.pdf", "/books/skip.txt"])
        try expectEqual(frontPaths, ["/books/old.pdf", "/books/new.epub"], "import should dedupe and ignore unsupported files")
        try expectEqual(storedPathsAfterImport(existing: items, droppedPaths: ["/books/old.pdf", "/books/new.epub", "/books/new.epub"]), ["/books/old.pdf", "/books/recent.pdf", "/books/mid.pdf", "/books/new.epub"], "import should not duplicate existing books and should append new books for later recent sorting")
    }

    static func testDroppedDocumentActions() throws {
        let items = [
            RecentDocumentItem(path: "/books/old.pdf", title: "Old", openedAt: Date(timeIntervalSince1970: 100)),
            RecentDocumentItem(path: "/books/recent.pdf", title: "Recent", openedAt: Date(timeIntervalSince1970: 300)),
            RecentDocumentItem(path: "/books/mid.pdf", title: "Mid", openedAt: Date(timeIntervalSince1970: 200))
        ]

        try expectEqual(droppedDocumentAction(paths: ["/books/a.pdf"]), .openSingle("/books/a.pdf"), "single dropped book should open directly")
        try expectEqual(
            droppedDocumentAction(paths: ["/books/a.pdf", "/books/b.epub", "/books/a.pdf", "/books/skip.txt"]),
            .showShelf(priorityPaths: ["/books/a.pdf", "/books/b.epub"]),
            "multiple dropped books should dedupe and keep shelf focus order"
        )
        try expectEqual(
            droppedDocumentAction(paths: ["/books/a.pdf", "/books/a.pdf"]),
            .showShelf(priorityPaths: ["/books/a.pdf"]),
            "multiple dropped files should open the shelf even when they dedupe to one book"
        )
        try expectEqual(
            sortedRecentDocuments(items, priorityPaths: ["/books/mid.pdf", "/books/old.pdf", "/books/mid.pdf"]).map(\.path),
            ["/books/mid.pdf", "/books/old.pdf", "/books/recent.pdf"],
            "open shelf import should move existing duplicate priority books to the front once"
        )
        try expectEqual(droppedDocumentAction(paths: ["/books/skip.txt"]), .none, "unsupported dropped files should be ignored")
    }
}
