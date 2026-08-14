import Foundation
import SQLite3

final class WordRecordSQLiteStore {
    static let shared = WordRecordSQLiteStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let shouldFailOperation: (String) -> Bool
    private let codec = WordRecordSQLiteJSONCodec()
    private lazy var pdfMapper = PDFWordRecordSQLiteMapper(codec: codec)
    private lazy var webMapper = WebWordRecordSQLiteMapper(codec: codec)

    init(databaseURL: URL?, shouldFailOperation: @escaping (String) -> Bool = { _ in false }) {
        self.shouldFailOperation = shouldFailOperation
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
            loadRecords(
                sql: PDFWordRecordSQLiteMapper.selectSQL,
                prepareOperation: "prepare load PDF records",
                bind: { bindText(documentID, at: .documentID, statement: $0) },
                decode: pdfMapper.decode
            )
        }
    }

    @discardableResult
    func savePDFRecords(documentID: String, records: [StoredPDFWordRecord]) -> Bool {
        locked {
            withTransaction {
                guard execute(sql: "DELETE FROM pdf_word_records WHERE document_id = ?", bindings: [documentID], operation: "delete existing PDF records") else {
                    return false
                }
                return records.allSatisfy { record in
                    insertPDFRecord(
                        documentID: documentID,
                        record: record,
                        prepareOperation: "prepare save PDF record",
                        stepOperation: "insert PDF record"
                    )
                }
            }
        }
    }

    @discardableResult
    func upsertPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        locked {
            insertPDFRecord(documentID: documentID, record: record)
        }
    }

    @discardableResult
    func upsertPDFRecords(documentID: String, records: [StoredPDFWordRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        return locked {
            withTransaction {
                records.allSatisfy { record in
                    insertPDFRecord(
                        documentID: documentID,
                        record: record,
                        prepareOperation: "prepare batch upsert PDF record",
                        stepOperation: "batch upsert PDF record"
                    )
                }
            }
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
            loadRecords(
                sql: WebWordRecordSQLiteMapper.selectSQL,
                prepareOperation: "prepare load web records",
                bind: { bindText(documentID, at: .documentID, statement: $0) },
                decode: webMapper.decode
            )
        }
    }

    @discardableResult
    func saveWebRecords(documentID: String, records: [StoredWebWordRecord]) -> Bool {
        locked {
            withTransaction {
                guard execute(sql: "DELETE FROM web_word_records WHERE document_id = ?", bindings: [documentID], operation: "delete existing web records") else {
                    return false
                }
                return records.allSatisfy { record in
                    insertWebRecord(
                        documentID: documentID,
                        record: record,
                        prepareOperation: "prepare save web record",
                        stepOperation: "insert web record"
                    )
                }
            }
        }
    }

    @discardableResult
    func upsertWebRecord(documentID: String, record: StoredWebWordRecord) -> Bool {
        locked {
            insertWebRecord(documentID: documentID, record: record)
        }
    }

    @discardableResult
    func upsertWebRecords(documentID: String, records: [StoredWebWordRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        return locked {
            withTransaction {
                records.allSatisfy { record in
                    insertWebRecord(
                        documentID: documentID,
                        record: record,
                        prepareOperation: "prepare batch upsert web record",
                        stepOperation: "batch upsert web record"
                    )
                }
            }
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
            dictionary_tags TEXT,
            dictionary_frequency INTEGER,
            created_at REAL NOT NULL,
            srs_json TEXT,
            text_anchor_json TEXT,
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
            dictionary_tags TEXT,
            dictionary_frequency INTEGER,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_web_word_records_document ON web_word_records(document_id);
        CREATE INDEX IF NOT EXISTS idx_web_word_records_word ON web_word_records(document_id, word);
        """
        executeRaw(sql, operation: "create word record tables")
        migrateColumns()
    }

    private func migrateColumns() {
        ensureColumn(table: "web_word_records", name: "occurrence_index", definition: "INTEGER")
        ensureColumn(table: "pdf_word_records", name: "dictionary_tags", definition: "TEXT")
        ensureColumn(table: "web_word_records", name: "dictionary_tags", definition: "TEXT")
        ensureColumn(table: "pdf_word_records", name: "dictionary_frequency", definition: "INTEGER")
        ensureColumn(table: "pdf_word_records", name: "text_anchor_json", definition: "TEXT")
        ensureColumn(table: "web_word_records", name: "dictionary_frequency", definition: "INTEGER")
    }

    private func ensureColumn(table: String, name: String, definition: String) {
        SQLiteSchemaMigrator.ensureColumn(
            db: db,
            table: table,
            name: name,
            definition: definition,
            logFailure: logSQLiteFailure,
            execute: { [weak self] sql, operation in
                self?.executeRaw(sql, operation: operation) ?? false
            }
        )
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func withTransaction(_ work: () -> Bool) -> Bool {
        SQLiteTransactionExecutor { [weak self] sql, operation in
            self?.executeRaw(sql, operation: operation) ?? false
        }.perform(work)
    }

    private func execute(sql: String, bindings: [String], operation: String) -> Bool {
        executeStatement(
            sql: sql,
            prepareOperation: "prepare \(operation)",
            stepOperation: operation
        ) { statement in
            for (offset, value) in bindings.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 1), value, -1, WORD_RECORD_SQLITE_TRANSIENT)
            }
            return true
        }
    }

    private func loadRecords<Record>(
        sql: String,
        prepareOperation: String,
        bind: (OpaquePointer?) -> Void,
        decode: (OpaquePointer?) -> Record?
    ) -> [Record] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure(prepareOperation)
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)

        var records: [Record] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = decode(statement) else { continue }
            records.append(record)
        }
        return records
    }

    private func executeStatement(
        sql: String,
        prepareOperation: String,
        stepOperation: String,
        bind: (OpaquePointer?) -> Bool
    ) -> Bool {
        guard !shouldFailOperation(prepareOperation) else {
            logInjectedFailure(prepareOperation)
            return false
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure(prepareOperation)
            return false
        }
        defer { sqlite3_finalize(statement) }
        guard bind(statement) else {
            NSLog("LeafReader word records: %@ failed because required record data could not be encoded", stepOperation)
            return false
        }
        guard !shouldFailOperation(stepOperation) else {
            logInjectedFailure(stepOperation)
            return false
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure(stepOperation)
            return false
        }
        return true
    }

    private func insertPDFRecord(
        documentID: String,
        record: StoredPDFWordRecord,
        prepareOperation: String = "prepare upsert PDF record",
        stepOperation: String = "upsert PDF record"
    ) -> Bool {
        executeStatement(
            sql: PDFWordRecordSQLiteMapper.insertSQL,
            prepareOperation: prepareOperation,
            stepOperation: stepOperation
        ) { statement in
            pdfMapper.bind(documentID: documentID, record: record, to: statement)
        }
    }

    private func insertWebRecord(
        documentID: String,
        record: StoredWebWordRecord,
        prepareOperation: String = "prepare upsert web record",
        stepOperation: String = "upsert web record"
    ) -> Bool {
        executeStatement(
            sql: WebWordRecordSQLiteMapper.insertSQL,
            prepareOperation: prepareOperation,
            stepOperation: stepOperation
        ) { statement in
            webMapper.bind(documentID: documentID, record: record, to: statement)
        }
    }

    private func deleteRecords(table: String, documentID: String, ids: [String]) -> Bool {
        guard !ids.isEmpty else { return true }
        let sql = "DELETE FROM \(table) WHERE document_id = ? AND id = ?"
        return withTransaction {
            ids.allSatisfy { id in
                executeStatement(
                    sql: sql,
                    prepareOperation: "prepare delete \(table) record",
                    stepOperation: "delete \(table) record"
                ) { statement in
                    sqlite3_bind_text(statement, 1, documentID, -1, WORD_RECORD_SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, id, -1, WORD_RECORD_SQLITE_TRANSIENT)
                    return true
                }
            }
        }
    }

    @discardableResult
    private func executeRaw(_ sql: String, operation: String) -> Bool {
        guard !shouldFailOperation(operation) else {
            logInjectedFailure(operation)
            return false
        }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result == SQLITE_OK {
            return true
        }
        let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage()
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        NSLog("LeafReader word records: SQLite %@ failed (%d, error=%@)", operation, result, message)
        return false
    }

    private func logSQLiteFailure(_ operation: String) {
        NSLog("LeafReader word records: SQLite %@ failed (error=%@)", operation, sqliteErrorMessage())
    }

    private func logInjectedFailure(_ operation: String) {
        NSLog("LeafReader word records: injected SQLite %@ failure", operation)
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
