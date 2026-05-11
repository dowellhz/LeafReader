import Foundation

struct StoredWebWordRecord: Codable {
    let id: String
    let word: String
    let context: String
    let scrollProgress: Double
    var question: String
    var answer: String
    let createdAt: Date
}

struct WebWordRecordStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageKey = "bookSession.\(fileMD5).webWordRecords"
    }

    func load() -> [StoredWebWordRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([StoredWebWordRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [StoredWebWordRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func existingRecord(in records: [StoredWebWordRecord], word: String, context: String) -> StoredWebWordRecord? {
        let normalizedWord = normalize(word)
        let normalizedContext = normalize(context)
        return records.first {
            normalize($0.word) == normalizedWord && normalize($0.context) == normalizedContext
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
