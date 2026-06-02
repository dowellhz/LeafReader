import Foundation

struct VocabularyLearningStats: Equatable {
    let totalCount: Int
    let reviewedTodayCount: Int
    let masteredCount: Int
    let recallRatePercent: Int?
    let streakDays: Int
}

struct VocabularyLearningStatDisplayItem: Equatable {
    let title: String
    let value: String
    let valueIdentifier: String
}

enum VocabularyLearningStatsCalculator {
    static func stats(
        records: [VocabularyExportRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> VocabularyLearningStats {
        let reviewedToday = records.filter { record in
            guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
            return calendar.isDate(lastReviewedAt, inSameDayAs: now)
        }.count
        let totalReviews = records.reduce(0) { $0 + $1.srs.reviewCount }
        let totalLapses = records.reduce(0) { $0 + $1.srs.lapseCount }
        let recallRate: Int? = totalReviews > 0
            ? Int((Double(max(0, totalReviews - totalLapses)) / Double(totalReviews) * 100).rounded())
            : nil

        return VocabularyLearningStats(
            totalCount: records.count,
            reviewedTodayCount: reviewedToday,
            masteredCount: records.filter { $0.srs.isMastered }.count,
            recallRatePercent: recallRate,
            streakDays: activeDayStreak(records: records, now: now, calendar: calendar)
        )
    }

    private static func activeDayStreak(
        records: [VocabularyExportRecord],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let activeDays = Set(records.compactMap { record -> Date? in
            guard let lastReviewedAt = record.srs.lastReviewedAt else { return nil }
            return calendar.startOfDay(for: lastReviewedAt)
        })
        var cursor = calendar.startOfDay(for: now)
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }
}

enum VocabularyLearningStatsPresenter {
    static let containerIdentifier = "vocabularyStatsContainer"
    private static let totalIdentifier = "vocabularyStatTotalValue"
    private static let reviewedTodayIdentifier = "vocabularyStatReviewedTodayValue"
    private static let masteredIdentifier = "vocabularyStatMasteredValue"
    private static let recallRateIdentifier = "vocabularyStatRecallRateValue"
    private static let streakIdentifier = "vocabularyStatStreakValue"

    static func items(for stats: VocabularyLearningStats) -> [VocabularyLearningStatDisplayItem] {
        [
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("总词数", "Words"),
                value: "\(stats.totalCount)",
                valueIdentifier: totalIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("今日复习", "Today"),
                value: "\(stats.reviewedTodayCount)",
                valueIdentifier: reviewedTodayIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("已掌握", "Mastered"),
                value: "\(stats.masteredCount)",
                valueIdentifier: masteredIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("正确率", "Recall"),
                value: recallRateText(stats.recallRatePercent),
                valueIdentifier: recallRateIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("连续天数", "Streak"),
                value: "\(stats.streakDays)",
                valueIdentifier: streakIdentifier
            )
        ]
    }

    static func recallRateText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "--"
    }
}
