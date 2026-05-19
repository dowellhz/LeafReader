import Foundation
import SQLite3

struct PDFEmbeddingChunk {
    let id: String
    let pageIndex: Int
    let chunkIndex: Int
    let text: String
}

final class PDFEmbeddingStore {
    static let defaultMaximumCacheBytes: Int64 = 1024 * 1024 * 1024

    private let db: OpaquePointer?
    private var cachedCacheSize: (bytes: Int64, measuredAt: Date)?
    private let cacheSizeTTL: TimeInterval = 2.0

    init?() {
        guard let directory = Self.cacheDirectory() else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("pdf-embeddings.sqlite3")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { return nil }
        db = handle
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    func embeddings(documentID: String, model: String, chunkIDs: [String]) -> [String: [Float]] {
        guard !chunkIDs.isEmpty else { return [:] }
        var result: [String: [Float]] = [:]
        let sql = "SELECT chunk_id, embedding FROM embeddings WHERE document_id = ? AND model = ? AND chunk_id = ?"
        for chunkID in chunkIDs {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)
            bind(model, at: 2, statement: statement)
            bind(chunkID, at: 3, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW,
               let idPointer = sqlite3_column_text(statement, 0),
               let blob = sqlite3_column_blob(statement, 1) {
                let id = String(cString: idPointer)
                let byteCount = Int(sqlite3_column_bytes(statement, 1))
                result[id] = Self.decodeEmbedding(blob: blob, byteCount: byteCount)
            }
        }
        if !result.isEmpty {
            touchDocument(documentID: documentID, model: model)
        }
        return result
    }

    func save(documentID: String, model: String, chunks: [PDFEmbeddingChunk], embeddings: [[Float]]) {
        guard chunks.count == embeddings.count else { return }
        let sql = """
        INSERT OR REPLACE INTO embeddings(document_id, model, chunk_id, page_index, chunk_index, text, embedding, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        for (chunk, embedding) in zip(chunks, embeddings) {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)
            bind(model, at: 2, statement: statement)
            bind(chunk.id, at: 3, statement: statement)
            sqlite3_bind_int(statement, 4, Int32(chunk.pageIndex))
            sqlite3_bind_int(statement, 5, Int32(chunk.chunkIndex))
            bind(chunk.text, at: 6, statement: statement)
            let data = Self.encodeEmbedding(embedding)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 7, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_double(statement, 8, Date().timeIntervalSince1970)
            sqlite3_step(statement)
        }
        invalidateCacheSize()
        if pruneIfNeeded(maximumBytes: Self.defaultMaximumCacheBytes) {
            vacuum()
        }
    }

    func deleteDocument(documentID: String) {
        execute(sql: "DELETE FROM embeddings WHERE document_id = ?", bindings: [documentID])
        invalidateCacheSize()
        vacuum()
    }

    func deleteAll() {
        execute(sql: "DELETE FROM embeddings")
        invalidateCacheSize()
        vacuum()
    }

    func cacheSizeBytes() -> Int64 {
        if let cachedCacheSize,
           Date().timeIntervalSince(cachedCacheSize.measuredAt) < cacheSizeTTL {
            return cachedCacheSize.bytes
        }
        let bytes = Self.cacheDatabaseURL().flatMap { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        } ?? 0
        cachedCacheSize = (bytes, Date())
        return bytes
    }

    func documentCount() -> Int {
        scalarInt(sql: "SELECT COUNT(DISTINCT document_id) FROM embeddings")
    }

    @discardableResult
    func pruneIfNeeded(maximumBytes: Int64) -> Bool {
        guard maximumBytes > 0 else { return false }
        var didDelete = false
        while cacheSizeBytes() > maximumBytes {
            guard let oldestDocumentID = oldestDocumentID() else { break }
            execute(sql: "DELETE FROM embeddings WHERE document_id = ?", bindings: [oldestDocumentID])
            invalidateCacheSize()
            didDelete = true
        }
        return didDelete
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS embeddings (
            document_id TEXT NOT NULL,
            model TEXT NOT NULL,
            chunk_id TEXT NOT NULL,
            page_index INTEGER NOT NULL,
            chunk_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            embedding BLOB NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(document_id, model, chunk_id)
        );
        CREATE INDEX IF NOT EXISTS idx_embeddings_document_model ON embeddings(document_id, model);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func oldestDocumentID() -> String? {
        let sql = """
        SELECT document_id
        FROM embeddings
        GROUP BY document_id
        ORDER BY MAX(updated_at) ASC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func touchDocument(documentID: String, model: String) {
        let sql = "UPDATE embeddings SET updated_at = ? WHERE document_id = ? AND model = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        bind(documentID, at: 2, statement: statement)
        bind(model, at: 3, statement: statement)
        sqlite3_step(statement)
    }

    private func scalarInt(sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(sql: String, bindings: [String] = []) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bind(value, at: Int32(offset + 1), statement: statement)
        }
        sqlite3_step(statement)
    }

    private func vacuum() {
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
        invalidateCacheSize()
    }

    private func invalidateCacheSize() {
        cachedCacheSize = nil
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
    }

    private static func cacheDatabaseURL() -> URL? {
        cacheDirectory()?.appendingPathComponent("pdf-embeddings.sqlite3")
    }

    private static func encodeEmbedding(_ embedding: [Float]) -> Data {
        var values = embedding
        return Data(bytes: &values, count: values.count * MemoryLayout<Float>.size)
    }

    private static func decodeEmbedding(blob: UnsafeRawPointer, byteCount: Int) -> [Float] {
        guard byteCount > 0, byteCount % MemoryLayout<Float>.size == 0 else { return [] }
        let count = byteCount / MemoryLayout<Float>.size
        let buffer = blob.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
