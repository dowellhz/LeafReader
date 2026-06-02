import Foundation

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

        try expectEqual(
            VocabularyTextPolicy.pdfSearchQueries(for: "Nine-\ntenths"),
            ["Nine-\ntenths", "Nine- tenths", "Nine-tenths"],
            "PDF search should include line-broken hyphen variants"
        )
        try expect(
            VocabularyTextPolicy.pdfSearchQueries(for: "Nine-\ntenths").contains("Nine-tenths"),
            "PDF search should match hyphenated words when PDFKit inserts a line break"
        )

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

    static func testVocabularyAnswerFormatter() throws {
        let answer = """
        ## **Induction**

        中文释义：
        • n. 归纳
        """
        try expectEqual(
            VocabularyAnswerFormatter.answerBody(answer, word: "induction"),
            "中文释义：\n• n. 归纳",
            "answer formatter should remove duplicate word heading and blank lines"
        )
        try expectEqual(
            VocabularyAnswerFormatter.normalizedHeading("__Induction ：__"),
            "induction",
            "heading normalization should trim markdown emphasis and punctuation"
        )
    }

    static func testVocabularyReviewCardSelector() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = vocabularyRecord(id: "first", word: "alpha", createdAt: createdAt)
        let second = vocabularyRecord(id: "second", word: "beta", createdAt: createdAt.addingTimeInterval(1))
        let records = [first, second]

        let session = VocabularyReviewSession()
        session.priority = .newWordsFirst
        session.reviewIndex = 8
        guard let initial = VocabularyReviewCardSelector.selection(records: records, session: session) else {
            throw TestFailure(description: "selector should return a review card")
        }
        try expectEqual(initial.record.word, "beta", "new words first should select newest due record")
        try expectEqual(initial.position, 2, "selector should clamp an out-of-range review index to the last visible card")
        try expectEqual(initial.total, 2, "selector should report visible review count")
        try expectEqual(session.reviewIndex, 1, "selector should clamp session review index")

        session.contextShown = true
        session.cardKey = session.key(for: first)
        guard let preserved = VocabularyReviewCardSelector.selection(records: records, session: session) else {
            throw TestFailure(description: "selector should preserve currently shown card")
        }
        try expectEqual(preserved.record.word, "alpha", "visible context card should remain selected")
        try expectEqual(preserved.position, 1, "preserved card should keep its visible queue position")
        try expectEqual(preserved.total, 2, "preserved card should keep total count")
    }

    static func testVocabularyDailyGoalPolicy() throws {
        let now = Date()
        let old = now.addingTimeInterval(-172_800)
        let reviewed = VocabularyExportRecord(
            ids: ["reviewed"],
            word: "reviewed",
            answer: "answer",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            location: "",
            context: "",
            createdAt: old,
            srs: VocabularySRSState.initial(createdAt: old).reviewed(grade: 3, at: now)
        )
        let pending = vocabularyRecord(id: "pending", word: "pending", createdAt: old)

        try expectEqual(VocabularyDailyGoalPolicy.normalizedGoal(0), 10, "invalid daily goal should use default")
        try expectEqual(
            VocabularyDailyGoalPolicy.reviewedTodayCount(records: [reviewed, pending]),
            1,
            "daily goal should count only records reviewed today"
        )
    }

    static func testVocabularyLearningStats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -3, to: now)!

        var reviewedToday = VocabularySRSState.initial(createdAt: older)
        reviewedToday.reviewCount = 3
        reviewedToday.lapseCount = 1
        reviewedToday.lastReviewedAt = now

        var mastered = VocabularySRSState.initial(createdAt: older)
        mastered.reviewCount = 2
        mastered.lastReviewedAt = yesterday
        mastered.activeRecallStreak = 3
        mastered.intervalDays = 7
        mastered.dueDate = Date().addingTimeInterval(86_400)

        let stats = VocabularyLearningStatsCalculator.stats(
            records: [
                vocabularyRecord(id: "today", word: "today", createdAt: older, srs: reviewedToday),
                vocabularyRecord(id: "mastered", word: "mastered", createdAt: older, srs: mastered),
                vocabularyRecord(id: "new", word: "new", createdAt: now)
            ],
            now: now,
            calendar: calendar
        )

        try expectEqual(stats.totalCount, 3, "stats should count all vocabulary records")
        try expectEqual(stats.reviewedTodayCount, 1, "stats should count records reviewed today")
        try expectEqual(stats.masteredCount, 1, "stats should count mastered records")
        try expectEqual(stats.recallRatePercent, 80, "stats should estimate recall rate from review lapses")
        try expectEqual(stats.streakDays, 2, "stats should count consecutive active review days ending today")
    }

    static func testSelectionToolbarConfiguration() throws {
        let offlineState = ReaderCapabilityState(
            isOnline: false,
            hasModelAPIKey: true,
            isLocalDictionaryInstalled: true
        )
        try expectEqual(offlineState.queryCapability, .offlineDictionary, "offline capability should prefer local dictionary mode")

        try expectEqual(
            ReaderQueryCapability.current(isOnline: false, hasModelAPIKey: true),
            .offlineDictionary,
            "offline state should use the local dictionary even when an API key exists"
        )
        try expectEqual(
            ReaderQueryCapability.current(isOnline: true, hasModelAPIKey: false),
            .needsModelConfiguration,
            "online state without an API key should prompt for model configuration"
        )
        try expectEqual(
            ReaderQueryCapability.current(isOnline: true, hasModelAPIKey: true),
            .modelAvailable,
            "online state with an API key should enable model actions"
        )

        let offlineWord = SelectionToolbarConfiguration.make(
            isVocabularySelection: true,
            queryCapability: .offlineDictionary,
            shouldShowSpeakAction: false
        )
        try expectEqual(offlineWord.contextAction, .addWord, "offline word selections should keep the word action")
        try expectEqual(offlineWord.displayMode, .offlineWord, "offline word selections should show only word/speak/copy actions")

        let needsKeyText = SelectionToolbarConfiguration.make(
            isVocabularySelection: false,
            queryCapability: .needsModelConfiguration,
            shouldShowSpeakAction: true
        )
        try expectEqual(needsKeyText.contextAction, .summarize, "non-word selections should keep summarize as their context action")
        try expectEqual(needsKeyText.displayMode, .needsModelKeyCopyOnly, "unconfigured model text selections should show copy plus settings")

        let full = SelectionToolbarConfiguration.make(
            isVocabularySelection: true,
            queryCapability: .modelAvailable,
            shouldShowSpeakAction: true
        )
        try expectEqual(full.displayMode, .full(showsSpeak: true), "configured online state should expose the full toolbar")
    }

    static func testLocalDictionaryFallbackRequiresOfflineState() throws {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        try expect(
            RequestAvailabilityPolicy.shouldUseLocalDictionaryFallback(for: timeout, isOnline: false),
            "offline network errors should use local dictionary fallback"
        )
        try expect(
            !RequestAvailabilityPolicy.shouldUseLocalDictionaryFallback(for: timeout, isOnline: true),
            "online network errors should surface the model error instead of silently using local dictionary"
        )
    }

    static func testVocabularyReviewDisplayRecordLoaderLoadsOnlyCurrentRecord() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = vocabularyRecord(id: "current", word: "induction", createdAt: createdAt)
        var lookedUpWords: [String] = []
        var persisted: [(String, VocabularyExportRecord)] = []

        let displayRecord = VocabularyReviewDisplayRecordLoader.displayRecord(
            for: record,
            metadataLookup: { word in
                lookedUpWords.append(word)
                return (tags: "cet6 gre", frequency: 500)
            },
            persistTags: { tags, record in
                persisted.append((tags, record))
            }
        )

        try expectEqual(lookedUpWords, ["induction"], "display loader should look up only the requested review card")
        try expectEqual(displayRecord.dictionaryTags, "cet6 gre", "display loader should attach dictionary tags to the current card")
        try expectEqual(persisted.map(\.0), ["cet6 gre"], "display loader should persist tags once for the current card")
    }

    private static func vocabularyRecord(
        id: String,
        word: String,
        createdAt: Date,
        srs: VocabularySRSState? = nil
    ) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: [id],
            word: word,
            answer: "\(word) answer",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            location: "",
            context: "",
            createdAt: createdAt,
            srs: srs ?? VocabularySRSState.initial(createdAt: createdAt)
        )
    }
}
