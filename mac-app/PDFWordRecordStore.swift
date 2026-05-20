import Cocoa

struct StoredPDFWordRecord: Codable {
    let id: String
    let word: String
    let pageIndex: Int
    let bounds: StoredPDFWordRect
    var context: String?
    var question: String
    var answer: String
    let createdAt: Date
    var srs: VocabularySRSState?
}

struct PDFWordRecordStore {
    private let defaults: UserDefaults
    private let documentID: String
    private let storageKey: String
    private let migrationKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        documentID = fileMD5
        storageKey = "bookSession.\(fileMD5).wordRecords"
        migrationKey = "\(storageKey).sqliteMigrated"
    }

    func load() -> [StoredPDFWordRecord] {
        let sqliteRecords = WordRecordSQLiteStore.shared.loadPDFRecords(documentID: documentID)
        if !sqliteRecords.isEmpty {
            return sqliteRecords
        }
        if defaults.bool(forKey: migrationKey) {
            return []
        }
        let legacyRecords = loadLegacyRecords()
        if !legacyRecords.isEmpty {
            if WordRecordSQLiteStore.shared.savePDFRecords(documentID: documentID, records: legacyRecords) {
                defaults.set(true, forKey: migrationKey)
            }
            return legacyRecords
        }
        return legacyRecords
    }

    func save(_ records: [StoredPDFWordRecord]) {
        if WordRecordSQLiteStore.shared.savePDFRecords(documentID: documentID, records: records) {
            defaults.set(true, forKey: migrationKey)
        }
    }

    @discardableResult
    func upsert(_ record: StoredPDFWordRecord) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.upsertPDFRecord(documentID: documentID, record: record)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func delete(ids: [String]) -> Bool {
        let didDelete = WordRecordSQLiteStore.shared.deletePDFRecords(documentID: documentID, ids: ids)
        if didDelete {
            defaults.set(true, forKey: migrationKey)
        }
        return didDelete
    }

    private func loadLegacyRecords() -> [StoredPDFWordRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([StoredPDFWordRecord].self, from: data)
        } catch {
            NSLog("LeafReader word records: failed to decode legacy PDF records (documentID=%@, error=%@)", documentID, error.localizedDescription)
            return []
        }
    }

    func recordKey(pageIndex: Int, bounds: CGRect) -> String {
        "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
    }

    func existingRecord(in records: [StoredPDFWordRecord], pageIndex: Int, bounds: CGRect) -> StoredPDFWordRecord? {
        let key = recordKey(pageIndex: pageIndex, bounds: bounds)
        return records.first { record in
            recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect) == key
        }
    }

    func linkedWordBubbles(from records: [StoredPDFWordRecord]) -> [AIChatPanel.LinkedWordBubble] {
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
}
