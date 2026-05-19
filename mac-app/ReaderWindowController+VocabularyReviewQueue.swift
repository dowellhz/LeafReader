import Cocoa

extension ReaderWindowController {
    func vocabularyRecords(_ records: [VocabularyExportRecord], matching filter: VocabularyFilter) -> [VocabularyExportRecord] {
        switch filter {
        case .due:
            return records
                .filter { record in
                    guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
                    return Calendar.current.isDateInToday(lastReviewedAt)
                }
                .sorted {
                    ($0.srs.lastReviewedAt ?? $0.createdAt) > ($1.srs.lastReviewedAt ?? $1.createdAt)
                }
        case .new:
            return records
                .filter { Calendar.current.isDateInToday($0.createdAt) }
                .sorted { $0.createdAt > $1.createdAt }
        case .all:
            return records.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func vocabularyReviewRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        let batchKeys = ensureVocabularyReviewBatch(records: records)
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[vocabularyReviewKey(for: record)] = record
        }
        return batchKeys.compactMap { key in
            guard let record = recordsByKey[key] else { return nil }
            if vocabularyReviewIsShowingCurrentCard(key: key) {
                return record
            }
            guard !vocabularyRecordIsDoneForToday(record) else { return nil }
            return record
        }
    }

    @discardableResult
    func ensureVocabularyReviewBatch(records: [VocabularyExportRecord]) -> [String] {
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[vocabularyReviewKey(for: record)] = record
        }
        let remainingCurrentBatch = vocabularyReviewBatchKeys.filter { key in
            guard let record = recordsByKey[key] else { return false }
            if vocabularyReviewIsShowingCurrentCard(key: key) {
                return true
            }
            return !vocabularyRecordIsDoneForToday(record)
        }
        if !remainingCurrentBatch.isEmpty {
            vocabularyReviewBatchKeys = remainingCurrentBatch
            return remainingCurrentBatch
        }

        let nextBatch = vocabularyReviewQueue(records)
            .filter { !vocabularyRecordIsDoneForToday($0) }
            .prefix(10)
            .map { vocabularyReviewKey(for: $0) }
        vocabularyReviewBatchKeys = Array(nextBatch)
        return vocabularyReviewBatchKeys
    }

    func vocabularyReviewQueue(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        let dueRecords = records
            .filter { $0.srs.isDue }
            .sorted {
                if $0.srs.isNew != $1.srs.isNew {
                    return !$0.srs.isNew
                }
                return $0.srs.dueDate < $1.srs.dueDate
            }
        if !dueRecords.isEmpty {
            return dueRecords
        }
        return records
            .filter { !$0.srs.isMastered }
            .sorted { $0.srs.dueDate < $1.srs.dueDate }
    }

    func vocabularyRecordIsDoneForToday(_ record: VocabularyExportRecord) -> Bool {
        guard let lastReviewedAt = record.srs.lastReviewedAt,
              Calendar.current.isDateInToday(lastReviewedAt) else { return false }
        return (record.srs.activeRecallStreak ?? 0) > 0 && record.srs.intervalDays >= 1 && !record.srs.isDue
    }

    func vocabularyReviewIsShowingCurrentCard(key: String) -> Bool {
        (vocabularyReviewContextShown || vocabularyReviewAnswerShown) && vocabularyReviewCardKey == key
    }

    func vocabularySummaryText(records: [VocabularyExportRecord], filter: VocabularyFilter) -> String {
        let count = vocabularyRecords(records, matching: filter).count
        switch filter {
        case .due:
            return AppText.localized("今日复习 \(count) 个单词", "\(count) reviewed today")
        case .new:
            return AppText.localized("今日新词 \(count) 个单词", "\(count) new today")
        case .all:
            return AppText.localized("本书全部 \(count) 个单词", "\(count) total words")
        }
    }

    func updateVocabularySummaryWithProgress(position: Int, total: Int) {
        guard let root = vocabularyPanel?.contentView,
              let summary = findView(identifier: "vocabularySummaryLabel", in: root) as? NSTextField else { return }
        summary.stringValue = "\(vocabularySummaryText(records: currentVocabularyExportRecords, filter: vocabularyReviewFilter)) · \(position) / \(total)"
    }
}
