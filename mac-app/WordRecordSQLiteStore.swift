import Foundation
import SQLite3

final class WordRecordSQLiteStore {
    static let shared = WordRecordSQLiteStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL?) {
        guard let url = databaseURL else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
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
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
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
            execute(sql: "DELETE FROM pdf_word_records WHERE document_id = ?", bindings: [documentID])

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
            SELECT id, word, context, scroll_progress, question, answer, created_at, srs_json
            FROM web_word_records
            WHERE document_id = ?
            ORDER BY created_at ASC, id ASC
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)

            var records: [StoredWebWordRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = stringColumn(statement, 0),
                      let word = stringColumn(statement, 1),
                      let context = stringColumn(statement, 2),
                      let question = stringColumn(statement, 4),
                      let answer = stringColumn(statement, 5) else {
                    continue
                }
                records.append(
                    StoredWebWordRecord(
                        id: id,
                        word: word,
                        context: context,
                        scrollProgress: sqlite3_column_double(statement, 3),
                        question: question,
                        answer: answer,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                        srs: decodeJSON(VocabularySRSState.self, from: optionalStringColumn(statement, 7))
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
            execute(sql: "DELETE FROM web_word_records WHERE document_id = ?", bindings: [documentID])

            let sql = """
            INSERT OR REPLACE INTO web_word_records(
                document_id, id, word, context, scroll_progress, question, answer, created_at, srs_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var didFail = false
            for record in records {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    didFail = true
                    break
                }
                bind(documentID, at: 1, statement: statement)
                bind(record.id, at: 2, statement: statement)
                bind(record.word, at: 3, statement: statement)
                bind(record.context, at: 4, statement: statement)
                sqlite3_bind_double(statement, 5, record.scrollProgress)
                bind(record.question, at: 6, statement: statement)
                bind(record.answer, at: 7, statement: statement)
                sqlite3_bind_double(statement, 8, record.createdAt.timeIntervalSince1970)
                bindOptional(encodeJSON(record.srs), at: 9, statement: statement)
                if sqlite3_step(statement) != SQLITE_DONE {
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
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func beginTransaction() -> Bool {
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK
    }

    private func commitTransaction() {
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func rollbackTransaction() {
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
    }

    private func execute(sql: String, bindings: [String]) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bind(value, at: Int32(offset + 1), statement: statement)
        }
        sqlite3_step(statement)
    }

    private func insertPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO pdf_word_records(
            document_id, id, word, page_index, bounds_json, context, question, answer, created_at, srs_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
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
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func insertWebRecord(documentID: String, record: StoredWebWordRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO web_word_records(
            document_id, id, word, context, scroll_progress, question, answer, created_at, srs_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(documentID, at: 1, statement: statement)
        bind(record.id, at: 2, statement: statement)
        bind(record.word, at: 3, statement: statement)
        bind(record.context, at: 4, statement: statement)
        sqlite3_bind_double(statement, 5, record.scrollProgress)
        bind(record.question, at: 6, statement: statement)
        bind(record.answer, at: 7, statement: statement)
        sqlite3_bind_double(statement, 8, record.createdAt.timeIntervalSince1970)
        bindOptional(encodeJSON(record.srs), at: 9, statement: statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func deleteRecords(table: String, documentID: String, ids: [String]) -> Bool {
        guard !ids.isEmpty else { return true }
        let sql = "DELETE FROM \(table) WHERE document_id = ? AND id = ?"
        guard beginTransaction() else { return false }
        var didFail = false
        for id in ids {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                didFail = true
                break
            }
            bind(documentID, at: 1, statement: statement)
            bind(id, at: 2, statement: statement)
            if sqlite3_step(statement) != SQLITE_DONE {
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

    private static func databaseDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
    }

    private static func defaultDatabaseURL() -> URL? {
        databaseDirectory()?.appendingPathComponent("word-records.sqlite3")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
