import Foundation

enum VocabularyReviewQueueBuilder {
    static func queue(
        records: [VocabularyExportRecord],
        priority: VocabularyReviewPriority
    ) -> [VocabularyExportRecord] {
        let dueRecords = records
            .filter { $0.srs.isDue }
            .sorted { prioritySort($0, $1, priority: priority) }
        if !dueRecords.isEmpty {
            return dueRecords
        }

        let fallbackRecords = records.filter { !$0.srs.isMastered }
        switch priority {
        case .oldWordsFirst:
            return fallbackRecords.sorted { $0.srs.dueDate < $1.srs.dueDate }
        case .newWordsFirst, .frequencyFirst:
            return fallbackRecords.sorted { prioritySort($0, $1, priority: priority) }
        }
    }

    static func prioritySort(
        _ lhs: VocabularyExportRecord,
        _ rhs: VocabularyExportRecord,
        priority: VocabularyReviewPriority
    ) -> Bool {
        switch priority {
        case .oldWordsFirst:
            if lhs.srs.isNew != rhs.srs.isNew {
                return !lhs.srs.isNew
            }
        case .newWordsFirst:
            if lhs.srs.isNew != rhs.srs.isNew {
                return lhs.srs.isNew
            }
        case .frequencyFirst:
            if lhs.dictionaryFrequency != rhs.dictionaryFrequency {
                switch (lhs.dictionaryFrequency, rhs.dictionaryFrequency) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }
        }
        return lhs.srs.dueDate < rhs.srs.dueDate
    }
}
