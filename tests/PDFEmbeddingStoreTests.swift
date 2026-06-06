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

private func testPruneRemovesCachedDocumentsOverLimit() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-embedding-prune-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("pdf-embeddings.sqlite3")
    guard let store = PDFEmbeddingStore(databaseURL: databaseURL) else {
        throw TestFailure(description: "failed to create temporary embedding store")
    }

    let chunk = PDFEmbeddingChunk(id: "chunk-1", pageIndex: 0, chunkIndex: 0, text: String(repeating: "text ", count: 200))
    let embedding = Array(repeating: Float(0.25), count: 256)
    store.save(documentID: "doc-1", model: "test-model", chunks: [chunk], embeddings: [embedding])
    store.save(documentID: "doc-2", model: "test-model", chunks: [chunk], embeddings: [embedding])

    try expectEqual(store.documentCount(), 2, "test setup should save both documents")
    try expectEqual(store.pruneIfNeeded(maximumBytes: 1), true, "prune should delete cache entries over the limit")
    try expectEqual(store.documentCount(), 0, "tiny cache limit should remove all cached documents")
}

private func testBatchSaveAndLookupRoundTripsEmbeddings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-embedding-batch-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("pdf-embeddings.sqlite3")
    guard let store = PDFEmbeddingStore(databaseURL: databaseURL) else {
        throw TestFailure(description: "failed to create temporary embedding store")
    }

    let chunks = [
        PDFEmbeddingChunk(id: "chunk-a", pageIndex: 0, chunkIndex: 0, text: "alpha"),
        PDFEmbeddingChunk(id: "chunk-b", pageIndex: 0, chunkIndex: 1, text: "beta"),
        PDFEmbeddingChunk(id: "chunk-c", pageIndex: 1, chunkIndex: 0, text: "gamma")
    ]
    let embeddings: [[Float]] = [
        [0.1, 0.2, 0.3],
        [1.1, 1.2, 1.3],
        [2.1, 2.2, 2.3]
    ]

    store.save(documentID: "doc-batch", model: "test-model", chunks: chunks, embeddings: embeddings)
    let loaded = store.embeddings(documentID: "doc-batch", model: "test-model", chunkIDs: ["chunk-c", "missing", "chunk-a"])

    try expectEqual(loaded.count, 2, "lookup should return only cached chunk IDs")
    try expectEqual(loaded["chunk-a"], embeddings[0], "lookup should round-trip the first embedding")
    try expectEqual(loaded["chunk-c"], embeddings[2], "lookup should round-trip the last embedding")
    try expectEqual(loaded["missing"], nil, "lookup should omit missing chunk IDs")
}

private func testDocumentAgentIndexClearsEmbeddingsWhenCacheModelChanges() throws {
    let index = PDFDocumentAgentIndex(text: "Alpha passage for embeddings.\n\nBeta passage for retrieval.")
    let chunks = index.indexableChunks
    guard let firstChunk = chunks.first else {
        throw TestFailure(description: "test index should contain chunks")
    }

    index.applyEmbeddings([firstChunk.id: [0.1, 0.2, 0.3]], modelID: "provider:old-model:http://localhost/embeddings")
    try expectEqual(index.embeddingCoverage.embedded, 1, "old model embedding should be applied")
    try expectEqual(index.embeddingCacheModelID, "provider:old-model:http://localhost/embeddings", "index should remember the embedding cache model")

    index.prepareForEmbeddingCacheModel("provider:new-model:http://localhost/embeddings")
    try expectEqual(index.embeddingCoverage.embedded, 0, "changing embedding cache model should clear in-memory embeddings")
    try expectEqual(index.embeddingCacheModelID, "provider:new-model:http://localhost/embeddings", "index should track the new embedding cache model")
    try expectEqual(index.missingEmbeddingChunks().count, chunks.count, "all chunks should be rebuilt for the new embedding model")
}

@main
struct PDFEmbeddingStoreTestRunner {
    static func main() {
        do {
            try testCacheSizeIncludesSQLiteSidecars()
            try testPruneRemovesCachedDocumentsOverLimit()
            try testBatchSaveAndLookupRoundTripsEmbeddings()
            try testDocumentAgentIndexClearsEmbeddingsWhenCacheModelChanges()
            print("PDFEmbeddingStoreTests passed")
        } catch {
            fputs("PDFEmbeddingStoreTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
