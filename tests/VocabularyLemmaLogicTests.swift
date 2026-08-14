import Foundation

enum VocabularyLemmaLogicTests {
    static func testGrouping() throws {
        let run = VocabularyLemmaResolver.identity(for: "run", context: "I run every morning.")
        let runs = VocabularyLemmaResolver.identity(for: "runs", context: "She runs every morning.")
        let running = VocabularyLemmaResolver.identity(for: "running", context: "She is running quickly.")
        try expectEqual(run.lemma, "run", "base verbs should preserve their lemma")
        try expectEqual(runs.groupingKey, run.groupingKey, "third-person verb forms should group with their lemma")
        try expectEqual(running.groupingKey, run.groupingKey, "participles should group with their lemma")

        let verbSaw = VocabularyLemmaResolver.identity(for: "saw", context: "I saw a bird.")
        let nounSaw = VocabularyLemmaResolver.identity(for: "saw", context: "The saw is sharp.")
        try expectEqual(verbSaw.lemma, "see", "known irregular verbs should use a stable lemma")
        try expect(verbSaw.groupingKey != nounSaw.groupingKey, "homographs with different lexical classes must not be grouped")

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let primaryIDs = VocabularyRelatedFormPolicy.primarySampleIDs([
            VocabularyWordSample(id: "running", word: "running", context: "She is running quickly.", createdAt: date),
            VocabularyWordSample(id: "runs", word: "runs", context: "She runs daily.", createdAt: date.addingTimeInterval(1)),
            VocabularyWordSample(id: "running-2", word: "running", context: "They are running.", createdAt: date.addingTimeInterval(2)),
            VocabularyWordSample(id: "saw-noun", word: "saw", context: "The saw is sharp.", createdAt: date.addingTimeInterval(3))
        ])
        try expectEqual(
            primaryIDs,
            Set(["running", "running-2", "saw-noun"]),
            "each lemma group should keep every occurrence of its primary saved surface"
        )

        let matches = VocabularyLemmaOccurrenceMatcher.matches(
            in: "I run. She runs. They are running. The saw is sharp.",
            groupingKeys: [run.groupingKey]
        )
        try expectEqual(matches.map(\.surface), ["run", "runs", "running"], "page scans should find only forms in the requested lemma group")
    }
}
