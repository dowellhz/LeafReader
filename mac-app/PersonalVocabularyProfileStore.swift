import Foundation
import SQLite3

private let PERSONAL_VOCABULARY_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class PersonalVocabularyProfileStore {
    static let shared = PersonalVocabularyProfileStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?

    init(databaseURL: URL?) {
        guard let url = databaseURL else {
            NSLog("LeafReader personal vocabulary: no database URL available")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            NSLog("LeafReader personal vocabulary: failed to create database directory at %@ (error=%@)", url.deletingLastPathComponent().path, error.localizedDescription)
            return
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            NSLog("LeafReader personal vocabulary: failed to open database at %@ (error=%@)", url.path, message)
            sqlite3_close(db)
            db = nil
            return
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    @discardableResult
    func recordExposure(documentID: String, text: String, date: Date = Date()) -> Bool {
        let counts = PersonalVocabularyTokenizer.lemmaCounts(in: text)
        guard !counts.isEmpty else { return true }
        return recordExposure(PersonalVocabularyExposure(documentID: documentID, lemmaCounts: counts, date: date))
    }

    @discardableResult
    func recordExposure(_ exposure: PersonalVocabularyExposure) -> Bool {
        locked {
            guard !exposure.documentID.isEmpty, !exposure.lemmaCounts.isEmpty else { return true }
            guard beginTransaction() else { return false }
            var didFail = false
            for (lemma, count) in exposure.lemmaCounts where count > 0 {
                guard upsertExposure(lemma: lemma, documentID: exposure.documentID, count: count, date: exposure.date) else {
                    didFail = true
                    break
                }
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
    func recordQuery(text: String, aiExplainCount: Int = 1, date: Date = Date()) -> Bool {
        let counts = PersonalVocabularyTokenizer.lemmaCounts(in: text)
        guard !counts.isEmpty else { return true }
        return locked {
            guard beginTransaction() else { return false }
            var didFail = false
            for lemma in counts.keys {
                guard upsertQuery(lemma: lemma, aiExplainCount: aiExplainCount, date: date) else {
                    didFail = true
                    break
                }
            }
            if didFail {
                rollbackTransaction()
                return false
            }
            commitTransaction()
            return true
        }
    }

    func loadProfile(lemma rawLemma: String) -> PersonalVocabularyProfile? {
        let lemma = PersonalVocabularyTokenizer.lemma(for: rawLemma)
        return locked {
            loadProfileLocked(lemma: lemma)
        }
    }

    func loadKnownProfiles(limit: Int = 200) -> [PersonalVocabularyProfile] {
        locked {
            loadProfilesLocked(statuses: [.known, .likelyKnown, .familiar], limit: limit)
        }
    }

    private func createTables() {
        let sql = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS personal_vocabulary_profiles (
            lemma TEXT PRIMARY KEY,
            surface_count INTEGER NOT NULL DEFAULT 0,
            seen_count INTEGER NOT NULL DEFAULT 0,
            unqueried_seen_count INTEGER NOT NULL DEFAULT 0,
            post_query_unqueried_seen_count INTEGER NOT NULL DEFAULT 0,
            queried_count INTEGER NOT NULL DEFAULT 0,
            ai_explain_count INTEGER NOT NULL DEFAULT 0,
            review_correct_count INTEGER NOT NULL DEFAULT 0,
            review_wrong_count INTEGER NOT NULL DEFAULT 0,
            documents_seen INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'observed',
            confidence REAL NOT NULL DEFAULT 0,
            last_seen_at REAL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS personal_vocabulary_document_seen (
            lemma TEXT NOT NULL,
            document_id TEXT NOT NULL,
            seen_count INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            PRIMARY KEY(lemma, document_id)
        );
        CREATE INDEX IF NOT EXISTS idx_personal_vocabulary_status ON personal_vocabulary_profiles(status, confidence);
        """
        executeRaw(sql, operation: "create personal vocabulary tables")
        addColumnIfNeeded(
            table: "personal_vocabulary_profiles",
            column: "post_query_unqueried_seen_count",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )
        cleanupNoiseProfiles()
    }

    func cleanupNoiseProfiles() {
        var noiseLemmas: [String] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            """
            SELECT lemma FROM personal_vocabulary_profiles
            WHERE queried_count = 0
              AND ai_explain_count = 0
              AND review_correct_count = 0
              AND review_wrong_count = 0
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            logSQLiteFailure("prepare personal vocabulary noise cleanup scan")
            return
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let lemma = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) else {
                continue
            }
            if !PersonalVocabularyTokenizer.isStoredLemmaTrackable(lemma) {
                noiseLemmas.append(lemma)
            }
        }
        guard !noiseLemmas.isEmpty else { return }
        guard beginTransaction() else { return }
        for lemma in noiseLemmas {
            guard deleteProfileLocked(lemma: lemma) else {
                rollbackTransaction()
                return
            }
        }
        commitTransaction()
    }

    private func upsertExposure(lemma: String, documentID: String, count: Int, date: Date) -> Bool {
        let documentWasNew = !hasDocumentSeen(lemma: lemma, documentID: documentID)
        guard executeStatement(
            sql: """
            INSERT INTO personal_vocabulary_document_seen (lemma, document_id, seen_count, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(lemma, document_id) DO UPDATE SET
              seen_count = seen_count + excluded.seen_count,
              updated_at = excluded.updated_at
            """,
            operation: "upsert personal vocabulary document exposure",
            bind: { statement in
                bindText(lemma, at: 1, statement: statement)
                bindText(documentID, at: 2, statement: statement)
                sqlite3_bind_int(statement, 3, Int32(count))
                sqlite3_bind_double(statement, 4, date.timeIntervalSince1970)
            }
        ) else {
            return false
        }

        let existing = loadProfileLocked(lemma: lemma)
        let seenCount = (existing?.seenCount ?? 0) + count
        let unqueriedSeenCount = (existing?.unqueriedSeenCount ?? 0) + count
        let queriedCount = existing?.queriedCount ?? 0
        let postQueryUnqueriedSeenCount = (existing?.postQueryUnqueriedSeenCount ?? 0) + (queriedCount > 0 ? count : 0)
        let aiExplainCount = existing?.aiExplainCount ?? 0
        let reviewCorrectCount = existing?.reviewCorrectCount ?? 0
        let reviewWrongCount = existing?.reviewWrongCount ?? 0
        let documentsSeen = (existing?.documentsSeen ?? 0) + (documentWasNew ? 1 : 0)
        return upsertProfile(
            lemma: lemma,
            surfaceCount: (existing?.surfaceCount ?? 0) + count,
            seenCount: seenCount,
            unqueriedSeenCount: unqueriedSeenCount,
            postQueryUnqueriedSeenCount: postQueryUnqueriedSeenCount,
            queriedCount: queriedCount,
            aiExplainCount: aiExplainCount,
            reviewCorrectCount: reviewCorrectCount,
            reviewWrongCount: reviewWrongCount,
            documentsSeen: documentsSeen,
            lastSeenAt: date,
            updatedAt: date
        )
    }

    private func upsertQuery(lemma: String, aiExplainCount addedAIExplainCount: Int, date: Date) -> Bool {
        let existing = loadProfileLocked(lemma: lemma)
        let seenCount = existing?.seenCount ?? 0
        let unqueriedSeenCount = existing?.unqueriedSeenCount ?? 0
        let queriedCount = (existing?.queriedCount ?? 0) + 1
        let aiExplainCount = (existing?.aiExplainCount ?? 0) + max(0, addedAIExplainCount)
        let reviewCorrectCount = existing?.reviewCorrectCount ?? 0
        let reviewWrongCount = existing?.reviewWrongCount ?? 0
        let documentsSeen = existing?.documentsSeen ?? 0
        return upsertProfile(
            lemma: lemma,
            surfaceCount: existing?.surfaceCount ?? 0,
            seenCount: seenCount,
            unqueriedSeenCount: unqueriedSeenCount,
            postQueryUnqueriedSeenCount: 0,
            queriedCount: queriedCount,
            aiExplainCount: aiExplainCount,
            reviewCorrectCount: reviewCorrectCount,
            reviewWrongCount: reviewWrongCount,
            documentsSeen: documentsSeen,
            lastSeenAt: existing?.lastSeenAt,
            updatedAt: date
        )
    }

    private func upsertProfile(
        lemma: String,
        surfaceCount: Int,
        seenCount: Int,
        unqueriedSeenCount: Int,
        postQueryUnqueriedSeenCount: Int,
        queriedCount: Int,
        aiExplainCount: Int,
        reviewCorrectCount: Int,
        reviewWrongCount: Int,
        documentsSeen: Int,
        lastSeenAt: Date?,
        updatedAt: Date
    ) -> Bool {
        let status = PersonalVocabularyProfilePolicy.status(
            seenCount: seenCount,
            unqueriedSeenCount: unqueriedSeenCount,
            postQueryUnqueriedSeenCount: postQueryUnqueriedSeenCount,
            queriedCount: queriedCount,
            reviewCorrectCount: reviewCorrectCount,
            reviewWrongCount: reviewWrongCount,
            documentsSeen: documentsSeen
        )
        let confidence = PersonalVocabularyProfilePolicy.confidence(
            seenCount: seenCount,
            unqueriedSeenCount: unqueriedSeenCount,
            postQueryUnqueriedSeenCount: postQueryUnqueriedSeenCount,
            queriedCount: queriedCount,
            reviewCorrectCount: reviewCorrectCount,
            reviewWrongCount: reviewWrongCount,
            documentsSeen: documentsSeen
        )
        return executeStatement(
            sql: """
            INSERT INTO personal_vocabulary_profiles (
              lemma, surface_count, seen_count, unqueried_seen_count, post_query_unqueried_seen_count, queried_count, ai_explain_count,
              review_correct_count, review_wrong_count, documents_seen, status, confidence, last_seen_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(lemma) DO UPDATE SET
              surface_count = excluded.surface_count,
              seen_count = excluded.seen_count,
              unqueried_seen_count = excluded.unqueried_seen_count,
              post_query_unqueried_seen_count = excluded.post_query_unqueried_seen_count,
              queried_count = excluded.queried_count,
              ai_explain_count = excluded.ai_explain_count,
              review_correct_count = excluded.review_correct_count,
              review_wrong_count = excluded.review_wrong_count,
              documents_seen = excluded.documents_seen,
              status = excluded.status,
              confidence = excluded.confidence,
              last_seen_at = excluded.last_seen_at,
              updated_at = excluded.updated_at
            """,
            operation: "upsert personal vocabulary profile"
        ) { statement in
            bindText(lemma, at: 1, statement: statement)
            sqlite3_bind_int(statement, 2, Int32(surfaceCount))
            sqlite3_bind_int(statement, 3, Int32(seenCount))
            sqlite3_bind_int(statement, 4, Int32(unqueriedSeenCount))
            sqlite3_bind_int(statement, 5, Int32(postQueryUnqueriedSeenCount))
            sqlite3_bind_int(statement, 6, Int32(queriedCount))
            sqlite3_bind_int(statement, 7, Int32(aiExplainCount))
            sqlite3_bind_int(statement, 8, Int32(reviewCorrectCount))
            sqlite3_bind_int(statement, 9, Int32(reviewWrongCount))
            sqlite3_bind_int(statement, 10, Int32(documentsSeen))
            bindText(status.rawValue, at: 11, statement: statement)
            sqlite3_bind_double(statement, 12, confidence)
            if let lastSeenAt {
                sqlite3_bind_double(statement, 13, lastSeenAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 13)
            }
            sqlite3_bind_double(statement, 14, updatedAt.timeIntervalSince1970)
        }
    }

    private func hasDocumentSeen(lemma: String, documentID: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT 1 FROM personal_vocabulary_document_seen WHERE lemma = ? AND document_id = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            logSQLiteFailure("prepare personal vocabulary document seen lookup")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bindText(lemma, at: 1, statement: statement)
        bindText(documentID, at: 2, statement: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func deleteProfileLocked(lemma: String) -> Bool {
        guard executeStatement(
            sql: "DELETE FROM personal_vocabulary_document_seen WHERE lemma = ?",
            operation: "delete personal vocabulary document noise",
            bind: { statement in
                bindText(lemma, at: 1, statement: statement)
            }
        ) else {
            return false
        }
        return executeStatement(
            sql: "DELETE FROM personal_vocabulary_profiles WHERE lemma = ?",
            operation: "delete personal vocabulary profile noise",
            bind: { statement in
                bindText(lemma, at: 1, statement: statement)
            }
        )
    }

    private func loadProfilesLocked(statuses: [PersonalVocabularyStatus], limit: Int) -> [PersonalVocabularyProfile] {
        guard !statuses.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ",")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            """
            SELECT lemma, surface_count, seen_count, unqueried_seen_count, post_query_unqueried_seen_count,
                   queried_count, ai_explain_count,
                   review_correct_count, review_wrong_count, documents_seen, status, confidence, last_seen_at, updated_at
            FROM personal_vocabulary_profiles
            WHERE status IN (\(placeholders))
            ORDER BY CASE status
              WHEN 'known' THEN 0
              WHEN 'likely_known' THEN 1
              WHEN 'familiar' THEN 2
              ELSE 3
            END, confidence DESC, seen_count DESC, lemma ASC
            LIMIT ?
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            logSQLiteFailure("prepare load personal vocabulary profiles")
            return []
        }
        defer { sqlite3_finalize(statement) }
        for (index, status) in statuses.enumerated() {
            bindText(status.rawValue, at: Int32(index + 1), statement: statement)
        }
        sqlite3_bind_int(statement, Int32(statuses.count + 1), Int32(max(1, limit)))

        var profiles: [PersonalVocabularyProfile] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            profiles.append(decodeProfile(statement: statement, fallbackLemma: ""))
        }
        return profiles
    }

    private func loadProfileLocked(lemma: String) -> PersonalVocabularyProfile? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            """
            SELECT lemma, surface_count, seen_count, unqueried_seen_count, post_query_unqueried_seen_count,
                   queried_count, ai_explain_count,
                   review_correct_count, review_wrong_count, documents_seen, status, confidence, last_seen_at, updated_at
            FROM personal_vocabulary_profiles WHERE lemma = ?
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            logSQLiteFailure("prepare load personal vocabulary profile")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bindText(lemma, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeProfile(statement: statement, fallbackLemma: lemma)
    }

    private func decodeProfile(statement: OpaquePointer?, fallbackLemma: String) -> PersonalVocabularyProfile {
        let statusText = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? PersonalVocabularyStatus.observed.rawValue
        let lastSeenAt = sqlite3_column_type(statement, 12) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 12))
        return PersonalVocabularyProfile(
            lemma: sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? fallbackLemma,
            surfaceCount: Int(sqlite3_column_int(statement, 1)),
            seenCount: Int(sqlite3_column_int(statement, 2)),
            unqueriedSeenCount: Int(sqlite3_column_int(statement, 3)),
            postQueryUnqueriedSeenCount: Int(sqlite3_column_int(statement, 4)),
            queriedCount: Int(sqlite3_column_int(statement, 5)),
            aiExplainCount: Int(sqlite3_column_int(statement, 6)),
            reviewCorrectCount: Int(sqlite3_column_int(statement, 7)),
            reviewWrongCount: Int(sqlite3_column_int(statement, 8)),
            documentsSeen: Int(sqlite3_column_int(statement, 9)),
            status: PersonalVocabularyStatus(rawValue: statusText) ?? .observed,
            confidence: sqlite3_column_double(statement, 11),
            lastSeenAt: lastSeenAt,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 13))
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

    private func executeStatement(sql: String, operation: String, bind: (OpaquePointer?) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare \(operation)")
            return false
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure(operation)
            return false
        }
        return true
    }

    @discardableResult
    private func executeRaw(_ sql: String, operation: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result == SQLITE_OK {
            return true
        }
        let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage()
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        NSLog("LeafReader personal vocabulary: SQLite %@ failed (%d, error=%@)", operation, result, message)
        return false
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) {
        guard !columnExists(table: table, column: column) else { return }
        executeRaw("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", operation: "add \(table).\(column)")
    }

    private func columnExists(table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare table info lookup")
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let columnName = sqlite3_column_text(statement, 1).map({ String(cString: $0) }) else {
                continue
            }
            if columnName == column {
                return true
            }
        }
        return false
    }

    private func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, PERSONAL_VOCABULARY_SQLITE_TRANSIENT)
    }

    private func logSQLiteFailure(_ operation: String) {
        NSLog("LeafReader personal vocabulary: SQLite %@ failed (error=%@)", operation, sqliteErrorMessage())
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
        databaseDirectory()?.appendingPathComponent("personal-vocabulary.sqlite3")
    }
}
