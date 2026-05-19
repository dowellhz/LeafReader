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
    private let databaseURL: URL
    private var cachedCacheSize: (bytes: Int64, measuredAt: Date)?
    private let cacheSizeTTL: TimeInterval = 2.0

    convenience init?() {
        guard let directory = Self.cacheDirectory() else { return nil }
        let url = directory.appendingPathComponent("pdf-embeddings.sqlite3")
        self.init(databaseURL: url)
    }

    init?(databaseURL: URL) {
        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK else {
            if let handle {
                let message = String(cString: sqlite3_errmsg(handle))
                NSLog("Leaf Reader PDFEmbeddingStore SQLite open failed: \(message)")
                sqlite3_close(handle)
            }
            return nil
        }
        db = handle
        self.databaseURL = databaseURL
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    func embeddings(documentID: String, model: String, chunkIDs: [String]) -> [String: [Float]] {
        guard !chunkIDs.isEmpty else { return [:] }
        var result: [String: [Float]] = [:]
        let sql = "SELECT chunk_id, embedding FROM embeddings WHERE document_id = ? AND model = ? AND chunk_id = ?"
        var statement: OpaquePointer?
        guard prepare(sql, statement: &statement, operation: "prepare embedding lookup") else { return [:] }
        defer { sqlite3_finalize(statement) }
        for chunkID in chunkIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(documentID, at: 1, statement: statement)
            bind(model, at: 2, statement: statement)
            bind(chunkID, at: 3, statement: statement)
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW,
               let idPointer = sqlite3_column_text(statement, 0),
               let blob = sqlite3_column_blob(statement, 1) {
                let id = String(cString: idPointer)
                let byteCount = Int(sqlite3_column_bytes(statement, 1))
                result[id] = Self.decodeEmbedding(blob: blob, byteCount: byteCount)
            } else if stepResult != SQLITE_DONE {
                logSQLiteError("lookup embedding row", result: stepResult)
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
        guard beginTransaction() else { return }
        var didWriteAllRows = true
        let updatedAt = Date().timeIntervalSince1970
        var statement: OpaquePointer?
        guard prepare(sql, statement: &statement, operation: "prepare embedding save") else {
            rollbackTransaction()
            return
        }
        defer { sqlite3_finalize(statement) }
        for (chunk, embedding) in zip(chunks, embeddings) {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
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
            sqlite3_bind_double(statement, 8, updatedAt)
            if !step(statement, operation: "save embedding row") {
                didWriteAllRows = false
                break
            }
        }
        guard didWriteAllRows, commitTransaction() else {
            rollbackTransaction()
            return
        }
        invalidateCacheSize()
        pruneIfNeeded(maximumBytes: Self.defaultMaximumCacheBytes)
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
        let bytes = Self.cacheSizeBytes(forDatabaseURL: databaseURL)
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
        var deletedDocumentIDs = Set<String>()
        while cacheSizeBytes() > maximumBytes {
            guard let oldestDocumentID = oldestDocumentID(),
                  !deletedDocumentIDs.contains(oldestDocumentID) else {
                break
            }
            guard execute(sql: "DELETE FROM embeddings WHERE document_id = ?", bindings: [oldestDocumentID]) else {
                break
            }
            deletedDocumentIDs.insert(oldestDocumentID)
            didDelete = true
            checkpoint()
            vacuum()
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
        exec(sql, operation: "create embedding tables")
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
        guard prepare(sql, statement: &statement, operation: "prepare oldest document lookup") else { return nil }
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
        guard prepare(sql, statement: &statement, operation: "prepare embedding document touch") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        bind(documentID, at: 2, statement: statement)
        bind(model, at: 3, statement: statement)
        step(statement, operation: "touch embedding document")
    }

    private func scalarInt(sql: String) -> Int {
        var statement: OpaquePointer?
        guard prepare(sql, statement: &statement, operation: "prepare scalar query") else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    @discardableResult
    private func execute(sql: String, bindings: [String] = []) -> Bool {
        var statement: OpaquePointer?
        guard prepare(sql, statement: &statement, operation: "prepare execute") else { return false }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bind(value, at: Int32(offset + 1), statement: statement)
        }
        return step(statement, operation: "execute statement")
    }

    @discardableResult
    private func prepare(_ sql: String, statement: inout OpaquePointer?, operation: String) -> Bool {
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            logSQLiteError(operation, result: result, sql: sql)
            return false
        }
        return true
    }

    @discardableResult
    private func step(_ statement: OpaquePointer?, operation: String) -> Bool {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            logSQLiteError(operation, result: result)
            return false
        }
        return true
    }

    @discardableResult
    private func exec(_ sql: String, operation: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage()
            sqlite3_free(errorMessage)
            NSLog("Leaf Reader PDFEmbeddingStore SQLite \(operation) failed: \(message)")
            return false
        }
        return true
    }

    private func beginTransaction() -> Bool {
        exec("BEGIN IMMEDIATE TRANSACTION", operation: "begin embedding save transaction")
    }

    private func commitTransaction() -> Bool {
        exec("COMMIT", operation: "commit embedding save transaction")
    }

    private func rollbackTransaction() {
        exec("ROLLBACK", operation: "rollback embedding save transaction")
    }

    private func vacuum() {
        checkpoint()
        exec("VACUUM", operation: "vacuum embedding cache")
        invalidateCacheSize()
    }

    private func checkpoint() {
        exec("PRAGMA wal_checkpoint(TRUNCATE)", operation: "checkpoint embedding cache")
        invalidateCacheSize()
    }

    private func invalidateCacheSize() {
        cachedCacheSize = nil
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func logSQLiteError(_ operation: String, result: Int32, sql: String? = nil) {
        let detail = sql.map { " SQL: \($0)" } ?? ""
        NSLog("Leaf Reader PDFEmbeddingStore SQLite \(operation) failed (\(result)): \(sqliteErrorMessage()).\(detail)")
    }

    private func sqliteErrorMessage() -> String {
        guard let pointer = sqlite3_errmsg(db) else { return "unknown error" }
        return String(cString: pointer)
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
    }

    private static func cacheDatabaseURL() -> URL? {
        cacheDirectory()?.appendingPathComponent("pdf-embeddings.sqlite3")
    }

    static func cacheSizeBytes(forDatabaseURL url: URL) -> Int64 {
        sqliteCacheFileURLs(forDatabaseURL: url).reduce(Int64(0)) { total, fileURL in
            let bytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + bytes
        }
    }

    private static func sqliteCacheFileURLs(forDatabaseURL url: URL) -> [URL] {
        [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
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
