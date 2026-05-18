import Foundation

struct StoredWebWordRecord: Codable {
    let id: String
    let word: String
    let context: String
    let occurrenceIndex: Int?
    let scrollProgress: Double
    var question: String
    var answer: String
    let createdAt: Date
    var srs: VocabularySRSState?
}

struct WebWordRecordStore {
    private let defaults: UserDefaults
    private let documentID: String
    private let storageKey: String
    private let migrationKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        documentID = fileMD5
        storageKey = "bookSession.\(fileMD5).webWordRecords"
        migrationKey = "\(storageKey).sqliteMigrated"
    }

    func load() -> [StoredWebWordRecord] {
        let sqliteRecords = WordRecordSQLiteStore.shared.loadWebRecords(documentID: documentID)
        if !sqliteRecords.isEmpty {
            return sqliteRecords
        }
        if defaults.bool(forKey: migrationKey) {
            return []
        }
        let legacyRecords = loadLegacyRecords()
        if !legacyRecords.isEmpty {
            if WordRecordSQLiteStore.shared.saveWebRecords(documentID: documentID, records: legacyRecords) {
                defaults.set(true, forKey: migrationKey)
            }
            return legacyRecords
        }
        return legacyRecords
    }

    func save(_ records: [StoredWebWordRecord]) {
        if WordRecordSQLiteStore.shared.saveWebRecords(documentID: documentID, records: records) {
            defaults.set(true, forKey: migrationKey)
        }
    }

    @discardableResult
    func upsert(_ record: StoredWebWordRecord) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.upsertWebRecord(documentID: documentID, record: record)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func delete(ids: [String]) -> Bool {
        let didDelete = WordRecordSQLiteStore.shared.deleteWebRecords(documentID: documentID, ids: ids)
        if didDelete {
            defaults.set(true, forKey: migrationKey)
        }
        return didDelete
    }

    private func loadLegacyRecords() -> [StoredWebWordRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([StoredWebWordRecord].self, from: data) else {
            return []
        }
        return records
    }

    func existingRecord(in records: [StoredWebWordRecord], word: String, context: String, occurrenceIndex: Int? = nil) -> StoredWebWordRecord? {
        let normalizedWord = normalize(word)
        let normalizedContext = normalize(context)
        return records.first {
            normalize($0.word) == normalizedWord
                && normalize($0.context) == normalizedContext
                && ($0.occurrenceIndex == occurrenceIndex || $0.occurrenceIndex == nil || occurrenceIndex == nil)
        }
    }

    func linkedWordBubbles(from records: [StoredWebWordRecord]) -> [AIChatPanel.LinkedWordBubble] {
        records
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                AIChatPanel.LinkedWordBubble(
                    id: $0.id,
                    word: $0.word,
                    question: $0.question,
                    answer: $0.answer
                )
            }
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
