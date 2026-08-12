import Foundation

enum PersonalVocabularyProfileSchema {
    static let createTablesSQL = """
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
        is_learning_tracked INTEGER NOT NULL DEFAULT 0,
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

    static let noiseCandidateSQL = """
    SELECT lemma FROM personal_vocabulary_profiles
    WHERE queried_count = 0
      AND ai_explain_count = 0
      AND review_correct_count = 0
      AND review_wrong_count = 0
    """

    static func defaultDatabaseURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("personal-vocabulary.sqlite3")
    }
}
