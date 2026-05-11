import Cocoa

struct StoredPDFWordRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct StoredPDFWordRecord: Codable {
    let id: String
    let word: String
    let pageIndex: Int
    let bounds: StoredPDFWordRect
    var question: String
    var answer: String
    let createdAt: Date
}

struct PDFWordRecordStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageKey = "bookSession.\(fileMD5).wordRecords"
    }

    func load() -> [StoredPDFWordRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([StoredPDFWordRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [StoredPDFWordRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
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
