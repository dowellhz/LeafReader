import Foundation
import SQLite3

final class WordRecordSQLiteStore {
    static let shared = WordRecordSQLiteStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL?) {
        guard let url = databaseURL else {
            NSLog("LeafReader word records: no database URL available")
            return
        }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("LeafReader word records: failed to create database directory at %@ (error=%@)", directory.path, error.localizedDescription)
            return
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            NSLog("LeafReader word records: failed to open database at %@ (error=%@)", url.path, message)
            sqlite3_close(db)
            db = nil
            return
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadPDFRecords(documentID: String) -> [StoredPDFWordRecord] {
        locked {
            let sql = """
            SELECT id, word, page_index, bounds_json, context, question, answer, created_at, srs_json
            FROM pdf_word_records
            WHERE document_id = ?
            ORDER BY created_at ASC, id ASC
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare load PDF records")
                return []
            }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)

            var records: [StoredPDFWordRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = stringColumn(statement, 0),
                      let word = stringColumn(statement, 1),
                      let boundsJSON = stringColumn(statement, 3),
                      let bounds = decodeJSON(StoredPDFWordRect.self, from: boundsJSON),
                      let question = stringColumn(statement, 5),
                      let answer = stringColumn(statement, 6) else {
                    continue
                }
                records.append(
                    StoredPDFWordRecord(
                        id: id,
                        word: word,
                        pageIndex: Int(sqlite3_column_int(statement, 2)),
                        bounds: bounds,
                        context: optionalStringColumn(statement, 4),
                        question: question,
                        answer: answer,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                        srs: decodeJSON(VocabularySRSState.self, from: optionalStringColumn(statement, 8))
                    )
                )
            }
            return records
        }
    }

    @discardableResult
    func savePDFRecords(documentID: String, records: [StoredPDFWordRecord]) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            _ = execute(sql: "DELETE FROM pdf_word_records WHERE document_id = ?", bindings: [documentID], operation: "delete existing PDF records")

            let sql = """
            INSERT OR REPLACE INTO pdf_word_records(
                document_id, id, word, page_index, bounds_json, context, question, answer, created_at, srs_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var didFail = false
            for record in records {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    logSQLiteFailure("prepare save PDF record")
                    didFail = true
                    break
                }
                bind(documentID, at: 1, statement: statement)
                bind(record.id, at: 2, statement: statement)
                bind(record.word, at: 3, statement: statement)
                sqlite3_bind_int(statement, 4, Int32(record.pageIndex))
                bind(encodeJSON(record.bounds) ?? "{}", at: 5, statement: statement)
                bindOptional(record.context, at: 6, statement: statement)
                bind(record.question, at: 7, statement: statement)
                bind(record.answer, at: 8, statement: statement)
                sqlite3_bind_double(statement, 9, record.createdAt.timeIntervalSince1970)
                bindOptional(encodeJSON(record.srs), at: 10, statement: statement)
                if sqlite3_step(statement) != SQLITE_DONE {
                    logSQLiteFailure("insert PDF record")
                    didFail = true
                }
                sqlite3_finalize(statement)
                if didFail { break }
            }
            if didFail {
                rollbackTransaction()
                return false
            }
            commitTransaction()
            return true
        }
    }

    @discardableResult
    func upsertPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        locked {
            insertPDFRecord(documentID: documentID, record: record)
        }
    }

    @discardableResult
    func deletePDFRecords(documentID: String, ids: [String]) -> Bool {
        locked {
            deleteRecords(table: "pdf_word_records", documentID: documentID, ids: ids)
        }
    }

    func loadWebRecords(documentID: String) -> [StoredWebWordRecord] {
        locked {
            let sql = """
            SELECT id, word, context, occurrence_index, scroll_progress, question, answer, created_at, srs_json
            FROM web_word_records
            WHERE document_id = ?
            ORDER BY created_at ASC, id ASC
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare load web records")
                return []
            }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)

            var records: [StoredWebWordRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = stringColumn(statement, 0),
                      let word = stringColumn(statement, 1),
                      let context = stringColumn(statement, 2),
                      let question = stringColumn(statement, 5),
                      let answer = stringColumn(statement, 6) else {
                    continue
                }
                records.append(
                    StoredWebWordRecord(
                        id: id,
                        word: word,
                        context: context,
                        occurrenceIndex: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3)),
                        scrollProgress: sqlite3_column_double(statement, 4),
                        question: question,
                        answer: answer,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                        srs: decodeJSON(VocabularySRSState.self, from: optionalStringColumn(statement, 8))
                    )
                )
            }
            return records
        }
    }

    @discardableResult
    func saveWebRecords(documentID: String, records: [StoredWebWordRecord]) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            _ = execute(sql: "DELETE FROM web_word_records WHERE document_id = ?", bindings: [documentID], operation: "delete existing web records")

            let sql = """
            INSERT OR REPLACE INTO web_word_records(
                document_id, id, word, context, occurrence_index, scroll_progress, question, answer, created_at, srs_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var didFail = false
            for record in records {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    logSQLiteFailure("prepare save web record")
                    didFail = true
                    break
                }
                bind(documentID, at: 1, statement: statement)
                bind(record.id, at: 2, statement: statement)
                bind(record.word, at: 3, statement: statement)
                bind(record.context, at: 4, statement: statement)
                bindOptionalInt(record.occurrenceIndex, at: 5, statement: statement)
                sqlite3_bind_double(statement, 6, record.scrollProgress)
                bind(record.question, at: 7, statement: statement)
                bind(record.answer, at: 8, statement: statement)
                sqlite3_bind_double(statement, 9, record.createdAt.timeIntervalSince1970)
                bindOptional(encodeJSON(record.srs), at: 10, statement: statement)
                if sqlite3_step(statement) != SQLITE_DONE {
                    logSQLiteFailure("insert web record")
                    didFail = true
                }
                sqlite3_finalize(statement)
                if didFail { break }
            }
            if didFail {
                rollbackTransaction()
                return false
            }
            commitTransaction()
            return true
        }
    }

    @discardableResult
    func upsertWebRecord(documentID: String, record: StoredWebWordRecord) -> Bool {
        locked {
            insertWebRecord(documentID: documentID, record: record)
        }
    }

    @discardableResult
    func deleteWebRecords(documentID: String, ids: [String]) -> Bool {
        locked {
            deleteRecords(table: "web_word_records", documentID: documentID, ids: ids)
        }
    }

    private func createTables() {
        let sql = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS pdf_word_records (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            word TEXT NOT NULL,
            page_index INTEGER NOT NULL,
            bounds_json TEXT NOT NULL,
            context TEXT,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_pdf_word_records_document ON pdf_word_records(document_id);
        CREATE INDEX IF NOT EXISTS idx_pdf_word_records_word ON pdf_word_records(document_id, word);
        CREATE TABLE IF NOT EXISTS web_word_records (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            word TEXT NOT NULL,
            context TEXT NOT NULL,
            occurrence_index INTEGER,
            scroll_progress REAL NOT NULL,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_web_word_records_document ON web_word_records(document_id);
        CREATE INDEX IF NOT EXISTS idx_web_word_records_word ON web_word_records(document_id, word);
        """
        executeRaw(sql, operation: "create word record tables")
        executeRaw(
            "ALTER TABLE web_word_records ADD COLUMN occurrence_index INTEGER",
            operation: "migrate web word occurrence index",
            allowDuplicateColumn: true
        )
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func beginTransaction() -> Bool {
        executeRaw("BEGIN IMMEDIATE TRANSACTION", operation: "begin transaction")
    }

    private func commitTransaction() {
        executeRaw("COMMIT", operation: "commit transaction")
    }

    private func rollbackTransaction() {
        executeRaw("ROLLBACK", operation: "rollback transaction")
    }

    private func execute(sql: String, bindings: [String], operation: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare \(operation)")
            return false
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bind(value, at: Int32(offset + 1), statement: statement)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure(operation)
            return false
        }
        return true
    }

    private func insertPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO pdf_word_records(
            document_id, id, word, page_index, bounds_json, context, question, answer, created_at, srs_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare upsert PDF record")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bind(documentID, at: 1, statement: statement)
        bind(record.id, at: 2, statement: statement)
        bind(record.word, at: 3, statement: statement)
        sqlite3_bind_int(statement, 4, Int32(record.pageIndex))
        bind(encodeJSON(record.bounds) ?? "{}", at: 5, statement: statement)
        bindOptional(record.context, at: 6, statement: statement)
        bind(record.question, at: 7, statement: statement)
        bind(record.answer, at: 8, statement: statement)
        sqlite3_bind_double(statement, 9, record.createdAt.timeIntervalSince1970)
        bindOptional(encodeJSON(record.srs), at: 10, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure("upsert PDF record")
            return false
        }
        return true
    }

    private func insertWebRecord(documentID: String, record: StoredWebWordRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO web_word_records(
            document_id, id, word, context, occurrence_index, scroll_progress, question, answer, created_at, srs_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare upsert web record")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bind(documentID, at: 1, statement: statement)
        bind(record.id, at: 2, statement: statement)
        bind(record.word, at: 3, statement: statement)
        bind(record.context, at: 4, statement: statement)
        bindOptionalInt(record.occurrenceIndex, at: 5, statement: statement)
        sqlite3_bind_double(statement, 6, record.scrollProgress)
        bind(record.question, at: 7, statement: statement)
        bind(record.answer, at: 8, statement: statement)
        sqlite3_bind_double(statement, 9, record.createdAt.timeIntervalSince1970)
        bindOptional(encodeJSON(record.srs), at: 10, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure("upsert web record")
            return false
        }
        return true
    }

    private func deleteRecords(table: String, documentID: String, ids: [String]) -> Bool {
        guard !ids.isEmpty else { return true }
        let sql = "DELETE FROM \(table) WHERE document_id = ? AND id = ?"
        guard beginTransaction() else { return false }
        var didFail = false
        for id in ids {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare delete \(table) record")
                didFail = true
                break
            }
            bind(documentID, at: 1, statement: statement)
            bind(id, at: 2, statement: statement)
            if sqlite3_step(statement) != SQLITE_DONE {
                logSQLiteFailure("delete \(table) record")
                didFail = true
            }
            sqlite3_finalize(statement)
            if didFail { break }
        }
        if didFail {
            rollbackTransaction()
            return false
        }
        commitTransaction()
        return true
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptional(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bind(value, at: index, statement: statement)
    }

    private func bindOptionalInt(_ value: Int?, at index: Int32, statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func optionalStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : stringColumn(statement, index)
    }

    private func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    private func executeRaw(_ sql: String, operation: String, allowDuplicateColumn: Bool = false) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result == SQLITE_OK {
            return true
        }
        let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage()
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        if allowDuplicateColumn && message.localizedCaseInsensitiveContains("duplicate column") {
            return true
        }
        NSLog("LeafReader word records: SQLite %@ failed (%d, error=%@)", operation, result, message)
        return false
    }

    private func logSQLiteFailure(_ operation: String) {
        NSLog("LeafReader word records: SQLite %@ failed (error=%@)", operation, sqliteErrorMessage())
    }

    private func sqliteErrorMessage() -> String {
        guard let db else { return "database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private static func databaseDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
    }

    private static func defaultDatabaseURL() -> URL? {
        databaseDirectory()?.appendingPathComponent("word-records.sqlite3")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
