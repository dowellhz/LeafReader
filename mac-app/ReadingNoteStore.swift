import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ReadingNoteStore {
    static let shared = ReadingNoteStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL?) {
        guard let url = databaseURL else {
            NSLog("LeafReader reading notes: no database URL available")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            NSLog("LeafReader reading notes: failed to create database directory at %@ (error=%@)", url.path, error.localizedDescription)
            return
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            NSLog("LeafReader reading notes: failed to open database at %@ (error=%@)", url.path, message)
            sqlite3_close(db)
            db = nil
            return
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    func load(documentID: String) -> [ReadingNote] {
        locked {
            guard let db else { return [] }
            let sql = """
            SELECT id, document_id, document_title, document_kind, quote, markdown, locator_json, created_at, updated_at, is_favorite
            FROM reading_notes
            WHERE document_id = ?
            ORDER BY created_at ASC, id ASC
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare load notes")
                return []
            }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)
            var notes: [ReadingNote] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = stringColumn(statement, 0),
                      let noteDocumentID = stringColumn(statement, 1),
                      let title = stringColumn(statement, 2),
                      let kind = stringColumn(statement, 3),
                      let quote = stringColumn(statement, 4),
                      let markdown = stringColumn(statement, 5),
                      let locatorJSON = stringColumn(statement, 6) else {
                    continue
                }
                let locator: ReadingNote.Locator
                do {
                    locator = try decodeLocator(locatorJSON)
                } catch {
                    NSLog("LeafReader reading notes: skipped unreadable locator (id=%@, error=%@)", id, error.localizedDescription)
                    continue
                }
                notes.append(ReadingNote(
                    id: id,
                    documentID: noteDocumentID,
                    documentTitle: title,
                    documentKind: kind,
                    quote: quote,
                    markdown: markdown,
                    locator: locator,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                    isFavorite: sqlite3_column_int(statement, 9) != 0
                ))
            }
            return notes
        }
    }

    @discardableResult
    func upsert(_ note: ReadingNote) -> Bool {
        locked {
            guard let db else { return false }
            let locatorJSON: String
            do {
                locatorJSON = try encodeLocator(note.locator)
            } catch {
                NSLog("LeafReader reading notes: encode locator failed (id=%@, error=%@)", note.id, error.localizedDescription)
                return false
            }
            let sql = """
            INSERT OR REPLACE INTO reading_notes(
                id, document_id, document_title, document_kind, quote, markdown, locator_json, created_at, updated_at, is_favorite
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare upsert note")
                return false
            }
            defer { sqlite3_finalize(statement) }
            bind(note.id, at: 1, statement: statement)
            bind(note.documentID, at: 2, statement: statement)
            bind(note.documentTitle, at: 3, statement: statement)
            bind(note.documentKind, at: 4, statement: statement)
            bind(note.quote, at: 5, statement: statement)
            bind(note.markdown, at: 6, statement: statement)
            bind(locatorJSON, at: 7, statement: statement)
            sqlite3_bind_double(statement, 8, note.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 9, note.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 10, note.isFavorite ? 1 : 0)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                logSQLiteFailure("upsert note")
                return false
            }
            return true
        }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        locked {
            guard let db else { return false }
            let sql = "DELETE FROM reading_notes WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                logSQLiteFailure("prepare delete note")
                return false
            }
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, statement: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                logSQLiteFailure("delete note")
                return false
            }
            return true
        }
    }

    func containsNotes(documentID: String) -> Bool {
        locked {
            guard let db else { return false }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "SELECT 1 FROM reading_notes WHERE document_id = ? LIMIT 1",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                logSQLiteFailure("prepare note presence lookup")
                return false
            }
            defer { sqlite3_finalize(statement) }
            bind(documentID, at: 1, statement: statement)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    private func createTables() {
        _ = execute(sql: """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS reading_notes (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            document_title TEXT NOT NULL,
            document_kind TEXT NOT NULL,
            quote TEXT NOT NULL,
            markdown TEXT NOT NULL,
            locator_json TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_reading_notes_document ON reading_notes(document_id, created_at);
        """, operation: "create reading notes table")
        SQLiteSchemaMigrator.ensureColumn(
            db: db,
            table: "reading_notes",
            name: "is_favorite",
            definition: "INTEGER NOT NULL DEFAULT 0",
            logFailure: logSQLiteFailure,
            execute: execute
        )
    }

    private func execute(sql: String, operation: String) -> Bool {
        guard let db else { return false }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            NSLog("LeafReader reading notes: %@ failed (%@)", operation, message)
            sqlite3_free(error)
            return false
        }
        return true
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func encodeLocator(_ locator: ReadingNote.Locator) throws -> String {
        let data = try encoder.encode(locator)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return value
    }

    private func decodeLocator(_ value: String) throws -> ReadingNote.Locator {
        guard let data = value.data(using: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return try decoder.decode(ReadingNote.Locator.self, from: data)
    }

    private func logSQLiteFailure(_ operation: String) {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        NSLog("LeafReader reading notes: %@ failed (%@)", operation, message)
    }

    private static func defaultDatabaseURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("reading-notes.sqlite")
    }
}
