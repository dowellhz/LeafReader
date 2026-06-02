import Foundation
import SQLite3

enum SQLiteSchemaMigrator {
    static func ensureColumn(
        db: OpaquePointer?,
        table: String,
        name: String,
        definition: String,
        logFailure: (String) -> Void,
        execute: (String, String) -> Bool
    ) {
        guard !columnExists(db: db, table: table, name: name, logFailure: logFailure) else { return }
        _ = execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition);", "migrate \(table).\(name)")
    }

    static func columnExists(
        db: OpaquePointer?,
        table: String,
        name: String,
        logFailure: (String) -> Void
    ) -> Bool {
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            logFailure("inspect \(table) columns")
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let value = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: value) == name {
                return true
            }
        }
        return false
    }
}
