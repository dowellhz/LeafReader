import Foundation
import SQLite3

struct ECDICTEntry: Equatable {
    let word: String
    let phonetic: String
    let definition: String
    let translation: String
    let pos: String
    let tags: String
    let bnc: String
    let frq: String
    let exchange: String
}

struct ECDICTDiagnosticInfo {
    let url: URL?
    let byteCount: Int64?
    let entryCount: Int?

    var isInstalled: Bool {
        url != nil
    }

    var detailText: String {
        guard let url else {
            return AppText.localized("ECDICT 未安装", "ECDICT missing")
        }
        var parts = [AppText.localized("ECDICT 已安装", "ECDICT installed")]
        if let entryCount {
            parts.append(AppText.localized("\(entryCount) 词", "\(entryCount) entries"))
        }
        if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        parts.append(url.lastPathComponent)
        return parts.joined(separator: " · ")
    }
}

final class ECDICTDictionary {
    static let shared = ECDICTDictionary()

    private enum LookupCacheValue {
        case hit(ECDICTEntry)
        case miss
    }

    private let databaseURLs: [URL]
    private let csvURLs: [URL]
    private var lookupCache: [String: LookupCacheValue] = [:]
    private let cacheLock = NSLock()
    private var sqliteDatabase: OpaquePointer?
    private var sqliteDatabaseURL: URL?
    private let sqliteLock = NSLock()

    init(databaseURLs: [URL]? = nil, csvURLs: [URL]? = nil) {
        self.databaseURLs = databaseURLs ?? Self.defaultDatabaseURLs()
        self.csvURLs = csvURLs ?? Self.defaultCSVURLs()
    }

    deinit {
        sqliteLock.lock()
        if let sqliteDatabase {
            sqlite3_close(sqliteDatabase)
        }
        sqliteDatabase = nil
        sqliteDatabaseURL = nil
        sqliteLock.unlock()
    }

    var isInstalled: Bool {
        databaseURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
            || csvURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func diagnosticInfo() -> ECDICTDiagnosticInfo {
        for url in databaseURLs where FileManager.default.fileExists(atPath: url.path) {
            return ECDICTDiagnosticInfo(
                url: url,
                byteCount: fileSize(at: url),
                entryCount: sqliteEntryCount(databaseURL: url)
            )
        }
        for url in csvURLs where FileManager.default.fileExists(atPath: url.path) {
            return ECDICTDiagnosticInfo(
                url: url,
                byteCount: fileSize(at: url),
                entryCount: csvEntryCount(csvURL: url)
            )
        }
        return ECDICTDiagnosticInfo(url: nil, byteCount: nil, entryCount: nil)
    }

    func lookup(_ query: String) -> ECDICTEntry? {
        let normalized = Self.lookupKey(query)
        guard !normalized.isEmpty else { return nil }
        if let cached = cachedLookup(normalized) {
            return cached
        }
        let entry = uncachedLookup(normalized)
        cacheLookup(entry, for: normalized)
        return entry
    }

    func cachedLookupOnly(_ query: String) -> ECDICTEntry? {
        let normalized = Self.lookupKey(query)
        guard !normalized.isEmpty,
              let cached = cachedLookup(normalized) else {
            return nil
        }
        return cached
    }

    private func uncachedLookup(_ normalized: String) -> ECDICTEntry? {
        for url in databaseURLs where FileManager.default.fileExists(atPath: url.path) {
            if let entry = lookupSQLite(normalized, databaseURL: url) {
                return entry
            }
        }
        for url in csvURLs where FileManager.default.fileExists(atPath: url.path) {
            if let entry = lookupCSV(normalized, csvURL: url) {
                return entry
            }
        }
        return nil
    }

    private func cachedLookup(_ key: String) -> ECDICTEntry?? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let value = lookupCache[key] else { return nil }
        switch value {
        case .hit(let entry):
            return entry
        case .miss:
            return .some(nil)
        }
    }

    private func cacheLookup(_ entry: ECDICTEntry?, for key: String) {
        cacheLock.lock()
        lookupCache[key] = entry.map(LookupCacheValue.hit) ?? .miss
        if lookupCache.count > 2000 {
            lookupCache.removeAll(keepingCapacity: true)
        }
        cacheLock.unlock()
    }

    func markdownAnswer(for query: String, context: String = "") -> String? {
        guard let entry = lookup(query) else { return nil }
        return ECDICTAnswerFormatter.markdownAnswer(for: entry, context: context)
    }

    static func lookupKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" || $0.isWhitespace }
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }

    private func lookupSQLite(_ key: String, databaseURL: URL) -> ECDICTEntry? {
        sqliteLock.lock()
        defer { sqliteLock.unlock() }

        guard let db = openSQLiteDatabase(databaseURL) else {
            return nil
        }

        for table in ["stardict", "ecdict", "dictionary"] {
            if let entry = lookupSQLite(key, db: db, table: table) {
                return entry
            }
        }
        return nil
    }

    private func openSQLiteDatabase(_ databaseURL: URL) -> OpaquePointer? {
        if sqliteDatabaseURL == databaseURL, let sqliteDatabase {
            return sqliteDatabase
        }
        if let sqliteDatabase {
            sqlite3_close(sqliteDatabase)
        }
        sqliteDatabase = nil
        sqliteDatabaseURL = nil

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db {
                sqlite3_close(db)
            }
            return nil
        }
        sqliteDatabase = db
        sqliteDatabaseURL = databaseURL
        return db
    }

    private func sqliteEntryCount(databaseURL: URL) -> Int? {
        sqliteLock.lock()
        defer { sqliteLock.unlock() }
        guard let db = openSQLiteDatabase(databaseURL) else { return nil }
        for table in ["stardict", "ecdict", "dictionary"] {
            if let count = sqliteEntryCount(db: db, table: table) {
                return count
            }
        }
        return nil
    }

    private func sqliteEntryCount(db: OpaquePointer, table: String) -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func csvEntryCount(csvURL: URL) -> Int? {
        guard let text = try? String(contentsOf: csvURL, encoding: .utf8) else { return nil }
        return max(0, csvRecords(in: text).count - 1)
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize.map(Int64.init)
    }

    private func lookupSQLite(_ key: String, db: OpaquePointer, table: String) -> ECDICTEntry? {
        if let entry = lookupSQLite(key, db: db, table: table, whereClause: "sw = ?", bindCount: 1) {
            return entry
        }
        // Keep this indexed. The bundled lite dictionary stores normalized lookup
        // keys in `sw`; a NOCASE fallback on `word` does a full scan with the
        // current schema and makes dictionary misses visibly slow.
        return lookupSQLite(key, db: db, table: table, whereClause: "word = ?", bindCount: 1)
    }

    private func lookupSQLite(
        _ key: String,
        db: OpaquePointer,
        table: String,
        whereClause: String,
        bindCount: Int32
    ) -> ECDICTEntry? {
        let sql = """
        SELECT word, phonetic, definition, translation, pos, tag, bnc, frq, exchange
        FROM \(table)
        WHERE \(whereClause)
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        for index in 1...bindCount {
            sqlite3_bind_text(statement, index, key, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return ECDICTEntry(
            word: stringColumn(statement, 0),
            phonetic: stringColumn(statement, 1),
            definition: normalizedBody(stringColumn(statement, 2)),
            translation: normalizedBody(stringColumn(statement, 3)),
            pos: stringColumn(statement, 4),
            tags: stringColumn(statement, 5),
            bnc: stringColumn(statement, 6),
            frq: stringColumn(statement, 7),
            exchange: stringColumn(statement, 8)
        )
    }

    private func lookupCSV(_ key: String, csvURL: URL) -> ECDICTEntry? {
        guard let text = try? String(contentsOf: csvURL, encoding: .utf8) else { return nil }
        var header: [String]?
        for record in csvRecords(in: text) {
            if header == nil {
                header = record
                continue
            }
            guard let header else { continue }
            let row = Dictionary(uniqueKeysWithValues: zip(header, record))
            guard Self.lookupKey(row["word"] ?? "") == key else { continue }
            return ECDICTEntry(
                word: row["word"] ?? "",
                phonetic: row["phonetic"] ?? "",
                definition: normalizedBody(row["definition"] ?? ""),
                translation: normalizedBody(row["translation"] ?? ""),
                pos: row["pos"] ?? "",
                tags: row["tag"] ?? "",
                bnc: row["bnc"] ?? "",
                frq: row["frq"] ?? "",
                exchange: row["exchange"] ?? ""
            )
        }
        return nil
    }

    private func csvRecords(in text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            record.append(field)
                            field = ""
                        } else if next == "\n" {
                            record.append(field)
                            records.append(record)
                            record = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if char == ",", !inQuotes {
                record.append(field)
                field = ""
            } else if char == "\n", !inQuotes {
                record.append(field)
                records.append(record)
                record = []
                field = ""
            } else if char != "\r" || inQuotes {
                field.append(char)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }

    private func normalizedBody(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private static func defaultDatabaseURLs() -> [URL] {
        dictionaryRoots().flatMap { root in
            ["ecdict.db", "ecdict.sqlite", "stardict.db", "stardict.sqlite"].map {
                root.appendingPathComponent($0)
            }
        }
    }

    private static func defaultCSVURLs() -> [URL] {
        dictionaryRoots().flatMap { root in
            ["ecdict.csv", "ecdict.mini.csv"].map { root.appendingPathComponent($0) }
        }
    }

    private static func dictionaryRoots() -> [URL] {
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent("ECDICT", isDirectory: true))
            roots.append(resourceURL)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("LeafReader/ECDICT", isDirectory: true))
        }
        roots.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/leafreader/ecdict", isDirectory: true)
        )
        return roots
    }
}

enum ECDICTAnswerFormatter {
    static func markdownAnswer(for entry: ECDICTEntry, context: String = "") -> String {
        var lines: [String] = ["**\(entry.word)**"]
        if !entry.phonetic.isEmpty {
            lines.append("/\(entry.phonetic)/")
        }
        if !entry.translation.isEmpty {
            lines.append("")
            lines.append(contentsOf: formattedLines(title: AppText.localized("中文释义", "Chinese"), body: entry.translation))
        }
        if !entry.definition.isEmpty {
            lines.append("")
            lines.append(contentsOf: formattedLines(title: AppText.localized("英文释义", "English"), body: entry.definition))
        }
        let metadata = metadataLine(for: entry)
        if !metadata.isEmpty {
            lines.append("")
            lines.append(metadata)
        }
        if !entry.exchange.isEmpty {
            lines.append("")
            lines.append("\(AppText.localized("词形", "Forms"))：\(entry.exchange)")
        }
        if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("> \(context.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lines.append("")
        lines.append(AppText.localized("来源：本地 ECDICT 词典。", "Source: local ECDICT dictionary."))
        return lines.joined(separator: "\n")
    }

    private static func formattedLines(title: String, body: String) -> [String] {
        [title + "："] + body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
    }

    private static func metadataLine(for entry: ECDICTEntry) -> String {
        var parts: [String] = []
        if !entry.pos.isEmpty { parts.append("POS: \(entry.pos)") }
        if !entry.tags.isEmpty { parts.append("Tags: \(entry.tags)") }
        if !entry.bnc.isEmpty { parts.append("BNC: \(entry.bnc)") }
        if !entry.frq.isEmpty { parts.append("FRQ: \(entry.frq)") }
        return parts.joined(separator: " · ")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
