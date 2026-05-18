import Cocoa
import Foundation

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
    srs: VocabularySRSState? = nil
) -> StoredPDFWordRecord {
    StoredPDFWordRecord(
        id: id,
        word: word,
        pageIndex: 4,
        bounds: StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 12)),
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

        do {
        let store = WordRecordSQLiteStore(databaseURL: dbURL)
        let first = pdfRecord(id: "pdf-a", word: "alpha", answer: "one", createdAt: 1, srs: srs)
        let updated = pdfRecord(id: "pdf-a", word: "alpha", answer: "updated", createdAt: 2, srs: srs)
        let second = pdfRecord(id: "pdf-b", word: "beta", answer: "two", createdAt: 3)
        let other = pdfRecord(id: "pdf-other", word: "other", answer: "other", createdAt: 4)

        assert(store.upsertPDFRecord(documentID: documentID, record: first), "PDF upsert should succeed")
        assert(store.upsertPDFRecord(documentID: otherDocumentID, record: other), "PDF upsert for another document should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: second), "PDF second upsert should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: updated), "PDF update upsert should succeed")

        let loadedPDF = store.loadPDFRecords(documentID: documentID)
        assert(loadedPDF.map(\.id) == ["pdf-a", "pdf-b"], "PDF records should load ordered records for one document only")
        assert(loadedPDF.first?.answer == "updated", "PDF upsert should replace existing rows")
        assert(loadedPDF.first?.srs?.reviewCount == 2, "PDF SRS state should round-trip through production SQLite store")
        assert(store.loadPDFRecords(documentID: otherDocumentID).map(\.id) == ["pdf-other"], "PDF records should stay scoped by document")

        assert(store.deletePDFRecords(documentID: documentID, ids: ["pdf-a"]), "PDF delete(ids:) should succeed")
        assert(store.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF delete(ids:) should remove only selected rows")

        let webFirst = webRecord(id: "web-a", word: "gamma", answer: "one", createdAt: 1, srs: srs)
        let webUpdated = webRecord(id: "web-a", word: "gamma", answer: "updated", createdAt: 2, srs: srs)
        let webSecond = webRecord(id: "web-b", word: "delta", answer: "two", createdAt: 3)
        assert(store.saveWebRecords(documentID: documentID, records: [webFirst, webSecond]), "Web full save should succeed")
        assert(store.upsertWebRecord(documentID: documentID, record: webUpdated), "Web upsert should succeed")

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

        try? FileManager.default.removeItem(at: dbDirectory)
        print("SQLiteWordRecordStoreTests passed")
    }
}
