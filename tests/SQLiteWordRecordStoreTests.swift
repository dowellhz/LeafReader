import Cocoa
import Foundation
import SQLite3

final class AIChatPanel {
    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }
}

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("SQLiteWordRecordStoreTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func pdfRecord(
    id: String,
    word: String,
    answer: String,
    createdAt: TimeInterval,
    textAnchor: TextQuoteAnchor? = nil,
    srs: VocabularySRSState? = nil
) -> StoredPDFWordRecord {
    StoredPDFWordRecord(
        id: id,
        word: word,
        pageIndex: 4,
        bounds: StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 12)),
        textAnchor: textAnchor,
        context: "pdf context",
        question: "What is \(word)?",
        answer: answer,
        createdAt: Date(timeIntervalSince1970: createdAt),
        srs: srs
    )
}

private func webRecord(
    id: String,
    word: String,
    answer: String,
    createdAt: TimeInterval,
    srs: VocabularySRSState? = nil
) -> StoredWebWordRecord {
    StoredWebWordRecord(
        id: id,
        word: word,
        context: "web context",
        occurrenceIndex: nil,
        scrollProgress: 0.42,
        question: "What is \(word)?",
        answer: answer,
        createdAt: Date(timeIntervalSince1970: createdAt),
        srs: srs
    )
}

@main
struct SQLiteWordRecordStoreTestRunner {
    static func main() {
        let dbDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-production-sqlite-word-tests-\(UUID().uuidString)")
        let dbURL = dbDirectory.appendingPathComponent("word-records.sqlite3")
        let documentID = "sqlite-production-test-doc"
        let otherDocumentID = "sqlite-production-other-doc"
        let srs = VocabularySRSState(
            easeFactor: 2.6,
            intervalDays: 3,
            repetition: 2,
            dueDate: Date(timeIntervalSince1970: 20),
            lastReviewedAt: Date(timeIntervalSince1970: 10),
            reviewCount: 2,
            lapseCount: 1,
            activeRecallStreak: 2,
            masteredAt: nil
        )
        let anchorSource = "alpha stable omega"
        let anchor = TextQuoteAnchor(
            unitOrdinal: 4,
            sourceRange: (anchorSource as NSString).range(of: "stable"),
            sourceText: anchorSource
        )

        do {
        let store = WordRecordSQLiteStore(databaseURL: dbURL)
        let first = pdfRecord(id: "pdf-a", word: "alpha", answer: "one", createdAt: 1, textAnchor: anchor, srs: srs)
        let updated = pdfRecord(id: "pdf-a", word: "alpha", answer: "updated", createdAt: 2, textAnchor: anchor, srs: srs)
        let second = pdfRecord(id: "pdf-b", word: "beta", answer: "two", createdAt: 3)
        let other = pdfRecord(id: "pdf-other", word: "other", answer: "other", createdAt: 4)

        assert(store.upsertPDFRecord(documentID: documentID, record: first), "PDF upsert should succeed")
        assert(store.upsertPDFRecord(documentID: otherDocumentID, record: other), "PDF upsert for another document should succeed")
        assert(store.upsertPDFRecords(documentID: documentID, records: [second, updated]), "PDF batch upsert should succeed")

        let loadedPDF = store.loadPDFRecords(documentID: documentID)
        assert(loadedPDF.map(\.id) == ["pdf-a", "pdf-b"], "PDF records should load ordered records for one document only")
        assert(loadedPDF.first?.answer == "updated", "PDF upsert should replace existing rows")
        assert(loadedPDF.first?.srs?.reviewCount == 2, "PDF SRS state should round-trip through production SQLite store")
        assert(loadedPDF.first?.textAnchor == anchor, "PDF semantic text anchor should round-trip through production SQLite store")
        assert(store.loadPDFRecords(documentID: otherDocumentID).map(\.id) == ["pdf-other"], "PDF records should stay scoped by document")

        assert(store.deletePDFRecords(documentID: documentID, ids: ["pdf-a"]), "PDF delete(ids:) should succeed")
        assert(store.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF delete(ids:) should remove only selected rows")

        let webFirst = webRecord(id: "web-a", word: "gamma", answer: "one", createdAt: 1, srs: srs)
        let webUpdated = webRecord(id: "web-a", word: "gamma", answer: "updated", createdAt: 2, srs: srs)
        let webSecond = webRecord(id: "web-b", word: "delta", answer: "two", createdAt: 3)
        assert(store.saveWebRecords(documentID: documentID, records: [webFirst, webSecond]), "Web full save should succeed")
        assert(store.upsertWebRecords(documentID: documentID, records: [webUpdated]), "Web batch upsert should succeed")

        let loadedWeb = store.loadWebRecords(documentID: documentID)
        assert(loadedWeb.map(\.id) == ["web-a", "web-b"], "Web records should load ordered records")
        assert(loadedWeb.first?.answer == "updated", "Web upsert should replace existing rows")
        assert(loadedWeb.first?.srs?.dueDate == Date(timeIntervalSince1970: 20), "Web SRS state should round-trip")
        assert(store.deleteWebRecords(documentID: documentID, ids: ["web-a"]), "Web delete(ids:) should succeed")
        assert(store.loadWebRecords(documentID: documentID).map(\.id) == ["web-b"], "Web delete(ids:) should remove only selected rows")
        }

        do {
        let reopened = WordRecordSQLiteStore(databaseURL: dbURL)
        assert(reopened.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF records should persist after reopening production SQLite store")
        assert(reopened.loadWebRecords(documentID: documentID).map(\.id) == ["web-b"], "Web records should persist after reopening production SQLite store")
        }

        let atomicDocumentID = "sqlite-atomic-test-doc"
        let original = pdfRecord(id: "original", word: "stable", answer: "keep", createdAt: 1)
        do {
        let seedStore = WordRecordSQLiteStore(databaseURL: dbURL)
        assert(seedStore.savePDFRecords(documentID: atomicDocumentID, records: [original]), "atomic test seed should save")
        }

        do {
        let deleteFailureStore = WordRecordSQLiteStore(databaseURL: dbURL) { $0 == "delete existing PDF records" }
        let replacement = pdfRecord(id: "replacement", word: "new", answer: "replace", createdAt: 2)
        assert(!deleteFailureStore.savePDFRecords(documentID: atomicDocumentID, records: [replacement]), "DELETE failure should fail the save")
        assert(deleteFailureStore.loadPDFRecords(documentID: atomicDocumentID).map(\.id) == ["original"], "DELETE failure should preserve existing records")
        }

        do {
        let insertFailureStore = WordRecordSQLiteStore(databaseURL: dbURL) { $0 == "insert PDF record" }
        let replacement = pdfRecord(id: "replacement", word: "new", answer: "replace", createdAt: 2)
        assert(!insertFailureStore.savePDFRecords(documentID: atomicDocumentID, records: [replacement]), "INSERT failure should fail the save")
        assert(insertFailureStore.loadPDFRecords(documentID: atomicDocumentID).map(\.id) == ["original"], "INSERT failure rollback should preserve existing records")
        }

        do {
        let commitFailureStore = WordRecordSQLiteStore(databaseURL: dbURL) { $0 == "commit transaction" }
        let replacement = pdfRecord(id: "replacement", word: "new", answer: "replace", createdAt: 2)
        assert(!commitFailureStore.savePDFRecords(documentID: atomicDocumentID, records: [replacement]), "COMMIT failure should fail the save")
        assert(commitFailureStore.loadPDFRecords(documentID: atomicDocumentID).map(\.id) == ["original"], "COMMIT failure rollback should preserve existing records")
        }

        let batchDocumentID = "sqlite-batch-atomic-test-doc"
        let batchOriginal = pdfRecord(id: "batch-original", word: "stable", answer: "keep", createdAt: 1)
        do {
        let seedStore = WordRecordSQLiteStore(databaseURL: dbURL)
        assert(seedStore.upsertPDFRecord(documentID: batchDocumentID, record: batchOriginal), "batch atomic test seed should save")
        }

        do {
        var insertCount = 0
        let batchFailureStore = WordRecordSQLiteStore(databaseURL: dbURL) { operation in
            guard operation == "batch upsert PDF record" else { return false }
            insertCount += 1
            return insertCount == 2
        }
        let updatedOriginal = pdfRecord(id: "batch-original", word: "stable", answer: "changed", createdAt: 2)
        let batchNew = pdfRecord(id: "batch-new", word: "new", answer: "new", createdAt: 3)
        assert(!batchFailureStore.upsertPDFRecords(documentID: batchDocumentID, records: [updatedOriginal, batchNew]), "batch INSERT failure should fail the upsert")
        let records = batchFailureStore.loadPDFRecords(documentID: batchDocumentID)
        assert(records.map(\.id) == ["batch-original"], "batch INSERT failure should not leave a partially inserted row")
        assert(records.first?.answer == "keep", "batch INSERT failure should roll back an earlier update")
        }

        do {
        let batchCommitFailureStore = WordRecordSQLiteStore(databaseURL: dbURL) { $0 == "commit transaction" }
        let updatedOriginal = pdfRecord(id: "batch-original", word: "stable", answer: "changed", createdAt: 2)
        assert(!batchCommitFailureStore.upsertPDFRecords(documentID: batchDocumentID, records: [updatedOriginal]), "batch COMMIT failure should fail the upsert")
        assert(batchCommitFailureStore.loadPDFRecords(documentID: batchDocumentID).first?.answer == "keep", "batch COMMIT failure should roll back the update")
        }

        let legacyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-word-anchor-migration-\(UUID().uuidString)")
        let legacyDatabaseURL = legacyDirectory.appendingPathComponent("word-records.sqlite3")
        try? FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        var legacyDB: OpaquePointer?
        assert(sqlite3_open(legacyDatabaseURL.path, &legacyDB) == SQLITE_OK, "legacy migration database should open")
        let legacySchema = """
        CREATE TABLE pdf_word_records (
            document_id TEXT NOT NULL, id TEXT NOT NULL, word TEXT NOT NULL,
            page_index INTEGER NOT NULL, bounds_json TEXT NOT NULL, context TEXT,
            question TEXT NOT NULL, answer TEXT NOT NULL, dictionary_tags TEXT,
            dictionary_frequency INTEGER, created_at REAL NOT NULL, srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        """
        assert(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil) == SQLITE_OK, "legacy PDF schema should be created")
        sqlite3_close(legacyDB)
        let migratedStore = WordRecordSQLiteStore(databaseURL: legacyDatabaseURL)
        let migratedRecord = pdfRecord(id: "migrated", word: "stable", answer: "kept", createdAt: 1, textAnchor: anchor)
        assert(migratedStore.upsertPDFRecord(documentID: "legacy", record: migratedRecord), "anchor migration should allow writes")
        assert(migratedStore.loadPDFRecords(documentID: "legacy").first?.textAnchor == anchor, "anchor migration should preserve semantic data")
        try? FileManager.default.removeItem(at: legacyDirectory)

        try? FileManager.default.removeItem(at: dbDirectory)
        print("SQLiteWordRecordStoreTests passed")
    }
}
