import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private func writeBytes(_ count: Int, to url: URL) throws {
    try Data(repeating: 1, count: count).write(to: url)
}

private func testCacheSizeIncludesSQLiteSidecars() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-embedding-store-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("pdf-embeddings.sqlite3")
    try writeBytes(11, to: databaseURL)
    try writeBytes(13, to: URL(fileURLWithPath: databaseURL.path + "-wal"))
    try writeBytes(17, to: URL(fileURLWithPath: databaseURL.path + "-shm"))

    try expectEqual(
        PDFEmbeddingStore.cacheSizeBytes(forDatabaseURL: databaseURL),
        41,
        "embedding cache size should include SQLite WAL and SHM sidecar files"
    )
}

@main
struct PDFEmbeddingStoreTestRunner {
    static func main() {
        do {
            try testCacheSizeIncludesSQLiteSidecars()
            print("PDFEmbeddingStoreTests passed")
        } catch {
            fputs("PDFEmbeddingStoreTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
