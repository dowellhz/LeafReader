import Foundation

private struct VocabularySRSState {
    var easeFactor: Double
    var intervalDays: Int
    var repetition: Int
    var dueDate: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    var lapseCount: Int
    var activeRecallStreak: Int?
    var masteredAt: Date?

    static func initial(createdAt: Date = Date()) -> VocabularySRSState {
        VocabularySRSState(
            easeFactor: 2.5,
            intervalDays: 0,
            repetition: 0,
            dueDate: createdAt,
            lastReviewedAt: nil,
            reviewCount: 0,
            lapseCount: 0,
            activeRecallStreak: 0,
            masteredAt: nil
        )
    }

    var isDue: Bool {
        dueDate <= Date()
    }

    var isMastered: Bool {
        (activeRecallStreak ?? 0) >= 3 && intervalDays >= 7 && !isDue
    }

    func reviewed(grade: Int, at date: Date = Date()) -> VocabularySRSState {
        let boundedGrade = min(max(grade, 1), 4)
        let wasMastered = isMastered
        var next = self
        next.reviewCount += 1
        next.lastReviewedAt = date

        if boundedGrade == 1 {
            next.repetition = 0
            next.intervalDays = 0
            next.lapseCount += 1
            next.activeRecallStreak = 0
            next.masteredAt = nil
            next.easeFactor = max(1.3, next.easeFactor - 0.25)
            next.dueDate = Calendar.current.date(byAdding: .minute, value: 10, to: date) ?? date
            return next
        }

        let intervals = boundedGrade == 2
            ? [1, 2, 4, 7, 15]
            : [1, 3, 7, 15, 30]
        let baseInterval = next.repetition < intervals.count
            ? intervals[next.repetition]
            : Int((Double(max(1, next.intervalDays)) * next.easeFactor).rounded())
        next.intervalDays = max(1, baseInterval)
        next.repetition += 1
        if boundedGrade >= 3 {
            next.activeRecallStreak = (next.activeRecallStreak ?? 0) + 1
        } else {
            next.activeRecallStreak = 0
        }
        next.easeFactor = max(1.3, next.easeFactor + next.easeDelta(for: boundedGrade))
        next.dueDate = Calendar.current.date(byAdding: .day, value: next.intervalDays, to: date) ?? date
        if !wasMastered && next.isMastered {
            next.masteredAt = date
        }
        return next
    }

    private func easeDelta(for grade: Int) -> Double {
        let q: Double
        switch grade {
        case 2:
            q = 3
        case 4:
            q = 5
        default:
            q = 4
        }
        return 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
    }
}

private struct StoredWordRecord: Equatable {
    let id: String
    var answer: String
    var srsReviewCount: Int
}

private struct InMemoryWordRecordStore {
    var sqliteRecords: [String: StoredWordRecord] = [:]
    var legacyRecords: [StoredWordRecord] = []
    var didMigrate = false

    mutating func load() -> [StoredWordRecord] {
        if !sqliteRecords.isEmpty {
            return sqliteRecords.values.sorted { $0.id < $1.id }
        }
        if didMigrate {
            return []
        }
        if !legacyRecords.isEmpty {
            for record in legacyRecords {
                sqliteRecords[record.id] = record
            }
            didMigrate = true
            return legacyRecords
        }
        return []
    }

    mutating func save(_ records: [StoredWordRecord]) {
        sqliteRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        didMigrate = true
    }

    mutating func upsert(_ record: StoredWordRecord) {
        sqliteRecords[record.id] = record
        didMigrate = true
    }

    mutating func delete(ids: [String]) {
        for id in ids {
            sqliteRecords.removeValue(forKey: id)
        }
        didMigrate = true
    }
}

enum VocabularyLogicTests {
    static func testVocabularySRS() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let initial = VocabularySRSState.initial(createdAt: date)

        let failed = initial.reviewed(grade: 1, at: date)
        try expectEqual(failed.intervalDays, 0, "failed review should stay same-day")
        try expectEqual(failed.repetition, 0, "failed review resets repetition")
        try expectEqual(failed.lapseCount, 1, "failed review increments lapse count")
        try expect(failed.dueDate > date, "failed review schedules short retry")

        let remembered = initial.reviewed(grade: 3, at: date)
        try expectEqual(remembered.intervalDays, 1, "first remembered review schedules one day")
        try expectEqual(remembered.repetition, 1, "remembered review increments repetition")
        try expectEqual(remembered.activeRecallStreak, 1, "remembered review increments recall streak")
    }

    static func testWordRecordIncrementalStore() throws {
        var store = InMemoryWordRecordStore()
        store.upsert(StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0))
        try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0)], "upsert should insert a record")

        store.upsert(StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2))
        try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2)], "upsert should update answer and SRS")

        store.upsert(StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0))
        store.delete(ids: ["a"])
        try expectEqual(store.load(), [StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0)], "delete(ids:) should remove only requested records")

        store.save([])
        try expectEqual(store.load(), [], "bulk clear should leave store empty")
    }

    static func testWordRecordLegacyMigrationDoesNotReviveClearedData() throws {
        var store = InMemoryWordRecordStore(legacyRecords: [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)])
        try expectEqual(store.load(), [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)], "first load should migrate legacy records")
        store.save([])
        try expectEqual(store.load(), [], "cleared migrated store should not reload legacy records")
    }

    static func testVocabularyTextPolicy() throws {
        try expect(VocabularyTextPolicy.isSingleEnglishWord("high-pitched"), "hyphenated words should count as one vocabulary word")
        try expect(VocabularyTextPolicy.isSingleEnglishWord("reader’s"), "curly apostrophes should be accepted in vocabulary words")
        try expect(!VocabularyTextPolicy.isSingleEnglishWord("two words"), "phrases should not count as a single word")
        try expectEqual(VocabularyTextPolicy.speakableWord(" high-pitched "), "high-pitched", "speakable words should be trimmed")

        try expect(VocabularyTextPolicy.isVocabularySelection("high-pitched voice"), "short English phrases should be vocabulary selections")
        try expect(!VocabularyTextPolicy.isVocabularySelection("one two three four five six"), "long phrases should not be vocabulary selections")
        try expect(!VocabularyTextPolicy.isVocabularySelection("high-pitched voice."), "punctuated sentences should not be saved as vocabulary items")

        guard let searchPattern = VocabularyTextPolicy.boundedSearchPattern(for: "high-pitched") else {
            throw TestFailure(description: "bounded search pattern should be built")
        }
        let searchRegex = try NSRegularExpression(pattern: searchPattern)
        let sample = "A high-pitched voice, not higher-pitched or low-pitched."
        let sampleRange = NSRange(location: 0, length: (sample as NSString).length)
        try expectEqual(searchRegex.matches(in: sample, range: sampleRange).count, 1, "bounded search should match the exact hyphenated word only")

        let emphasisPattern = VocabularyTextPolicy.emphasisPattern(for: "high-pitched")
        let emphasisRegex = try NSRegularExpression(pattern: emphasisPattern, options: [.caseInsensitive])
        try expectEqual(emphasisRegex.matches(in: sample, range: sampleRange).count, 1, "emphasis should use the same word boundary rule")
    }

    static func testVocabularyExporter() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            VocabularyExporter.Record(word: "alpha", answer: " first answer ", location: "p. 1", context: "context", source: "Book", createdAt: createdAt),
            VocabularyExporter.Record(word: "empty", answer: "   ", location: "p. 2", context: "", source: "Book", createdAt: createdAt)
        ]
        let exportable = VocabularyExporter.exportableRecords(records)
        try expectEqual(exportable.map(\.word), ["alpha"], "empty answers should not be exported")
        try expectEqual(VocabularyExporter.csvEscaped("a,\"b\""), "\"a,\"\"b\"\"\"", "CSV values should quote and escape quotes")
        try expectEqual(VocabularyExporter.safeFileName("A/B?C:D"), "A-B-C-D", "unsafe filename characters should be replaced")

        let markdown = VocabularyExporter.markdown(
            records: exportable,
            documentTitle: "Book",
            labels: VocabularyExporter.MarkdownLabels(
                titleSuffix: "Vocabulary",
                exportedAt: "Exported at",
                wordCount: "Word count",
                location: "Location",
                context: "Context"
            ),
            exportedAt: createdAt
        ) { record in
            record.answer
        }
        try expect(markdown.contains("# Book Vocabulary"), "markdown should include title")
        try expect(markdown.contains("- Context：context"), "markdown should include non-empty context")

        let csv = VocabularyExporter.csv(records: exportable) { record in
            record.answer
        }
        try expect(csv.contains("Front,Back,Page,Context,Source,Created At"), "CSV should include header")
        try expect(csv.contains("\"alpha\",\" first answer \",\"p. 1\",\"context\",\"Book\""), "CSV should include escaped record")
    }
}
