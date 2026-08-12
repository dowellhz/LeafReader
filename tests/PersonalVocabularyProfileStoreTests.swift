import Foundation
import SQLite3

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("PersonalVocabularyProfileStoreTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func executeSQL(_ sql: String, databaseURL: URL) {
    var db: OpaquePointer?
    assert(sqlite3_open(databaseURL.path, &db) == SQLITE_OK, "test database should open for direct SQL")
    defer { sqlite3_close(db) }
    var errorMessage: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    if result != SQLITE_OK {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        assert(false, "direct SQL failed: \(message)")
    }
}

@main
struct PersonalVocabularyProfileStoreTestRunner {
    static func main() {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-personal-vocabulary-\(UUID().uuidString).sqlite3")
        let store = PersonalVocabularyProfileStore(databaseURL: dbURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        assert(store.recordExposure(documentID: "book-a", text: "The Gravity gravity roistering.", date: date), "exposure should save")
        assert(store.loadProfile(lemma: "the") == nil, "stop words should not be stored as vocabulary profiles")
        assert(store.recordExposure(documentID: "book-a", text: "FREE eBOOKS AT PLANET eBOOK.COM\n21", date: date), "footer exposure should be ignored without failure")
        assert(store.loadProfile(lemma: "planet") == nil, "footer words should not be stored")
        assert(store.loadProfile(lemma: "ebook") == nil, "ebook footer words should not be stored")
        guard let gravity = store.loadProfile(lemma: "gravity") else {
            assert(false, "gravity profile should load")
            return
        }
        assert(gravity.seenCount == 2, "seen count should aggregate duplicate tokens")
        assert(gravity.unqueriedSeenCount == 2, "unqueried seen count should track exposure")
        assert(gravity.documentsSeen == 1, "first document should count once")

        assert(store.recordExposure(documentID: "book-a", text: "gravity", date: date), "same document exposure should save")
        assert(store.loadProfile(lemma: "gravity")?.documentsSeen == 1, "same document should not increment documents_seen")

        assert(store.recordExposure(documentID: "book-b", text: "gravity", date: date), "second document exposure should save")
        assert(store.recordExposure(documentID: "book-c", text: "gravity", date: date), "third document exposure should save")
        guard let known = store.loadProfile(lemma: "gravity") else {
            assert(false, "updated gravity profile should load")
            return
        }
        assert(known.documentsSeen == 3, "documents seen should count distinct documents")
        assert(known.status == .known, "repeated unqueried exposure without queries should become known")

        assert(store.recordQuery(text: "Gravity", date: date), "query should save")
        guard let queried = store.loadProfile(lemma: "gravity") else {
            assert(false, "queried gravity profile should load")
            return
        }
        assert(queried.queriedCount == 1, "query count should increment")
        assert(queried.aiExplainCount == 1, "AI explain count should increment")
        assert(queried.isLearningTracked, "query should mark the word as learning tracked")
        assert(queried.postQueryUnqueriedSeenCount == 0, "query should reset post-query unqueried exposure")
        assert(queried.status == .learning, "queried words should return to learning")
        assert(store.loadKnownProfiles().allSatisfy { $0.lemma != "gravity" }, "queried learning words should not be returned as known profiles")

        assert(store.recordExposure(documentID: "book-d", text: String(repeating: "gravity ", count: 4), date: date), "post-query exposure should save")
        guard let recovered = store.loadProfile(lemma: "gravity") else {
            assert(false, "recovered gravity profile should load")
            return
        }
        assert(recovered.postQueryUnqueriedSeenCount == 4, "post-query unqueried exposure should accumulate after query")
        assert(recovered.status == .learning, "queried words should not recover to known from unqueried reading alone")
        assert(store.loadKnownProfiles().allSatisfy { $0.lemma != "gravity" }, "tracked learning words should stay out of known profiles")

        executeSQL(
            """
            INSERT INTO personal_vocabulary_profiles (
              lemma, surface_count, seen_count, unqueried_seen_count, post_query_unqueried_seen_count, queried_count, ai_explain_count,
              review_correct_count, review_wrong_count, documents_seen, status, confidence, updated_at
            ) VALUES
              ('the', 10, 10, 10, 0, 0, 0, 0, 0, 1, 'known', 0.5, 1800000000),
              ('ebook', 10, 10, 10, 0, 0, 0, 0, 0, 1, 'known', 0.5, 1800000000),
              ('kept-query', 1, 1, 1, 0, 1, 1, 0, 0, 1, 'learning', 0.1, 1800000000);
            INSERT INTO personal_vocabulary_document_seen (lemma, document_id, seen_count, updated_at) VALUES
              ('the', 'book-a', 10, 1800000000),
              ('ebook', 'book-a', 10, 1800000000),
              ('kept-query', 'book-a', 1, 1800000000);
            """,
            databaseURL: dbURL
        )
        store.cleanupNoiseProfiles()
        assert(store.loadProfile(lemma: "the") == nil, "cleanup should remove stored stop-word noise")
        assert(store.loadProfile(lemma: "ebook") == nil, "cleanup should remove stored footer-fragment noise")
        assert(store.loadProfile(lemma: "kept-query") != nil, "cleanup should keep records with explicit query evidence")

        assert(store.recordExposure(documentID: "book-a", text: String(repeating: "roistering ", count: 4), date: date), "known-list exposure should save")
        let knownProfiles = store.loadKnownProfiles()
        assert(knownProfiles.contains { $0.lemma == "roistering" && $0.status == .known }, "known profile query should return inferred known words")

        print("PersonalVocabularyProfileStoreTests passed")
    }
}
