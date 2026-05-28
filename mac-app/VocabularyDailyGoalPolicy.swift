import Foundation

enum VocabularyDailyGoalPolicy {
    static let defaultGoal = 10
    static let options = [5, 10, 20, 30, 50]

    static func normalizedGoal(_ goal: Int) -> Int {
        guard goal > 0 else { return defaultGoal }
        return goal
    }

    static func reviewedTodayCount(records: [VocabularyExportRecord], calendar: Calendar = .current) -> Int {
        records.filter { record in
            guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
            return calendar.isDateInToday(lastReviewedAt)
        }.count
    }

    static func progressText(records: [VocabularyExportRecord], goal: Int) -> String {
        let normalizedGoal = normalizedGoal(goal)
        let reviewed = reviewedTodayCount(records: records)
        return AppText.localized(
            "今日目标 \(min(reviewed, normalizedGoal)) / \(normalizedGoal)",
            "Daily goal \(min(reviewed, normalizedGoal)) / \(normalizedGoal)"
        )
    }
}
