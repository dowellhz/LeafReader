import Foundation

struct VocabularySRSState: Codable {
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

    var isNew: Bool {
        reviewCount == 0
    }

    var isMastered: Bool {
        (activeRecallStreak ?? 0) >= 3 && intervalDays >= 7 && !isDue
    }

    var masteredToday: Bool {
        guard let masteredAt else { return false }
        return Calendar.current.isDateInToday(masteredAt)
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
        next.easeFactor = max(1.3, next.easeFactor + easeDelta(for: boundedGrade))
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
