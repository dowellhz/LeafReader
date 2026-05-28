import Foundation

final class VocabularyReviewSession {
    let listPageSize = 20
    var filter: VocabularyFilter = .due
    var priority: VocabularyReviewPriority = .frequencyFirst
    var reviewIndex = 0
    var listPageIndex = 0
    var contextShown = false
    var answerShown = false
    var listModeEnabled = false
    var cardKey: String?
    var cardShownAt = Date()
    var answerShownAt: Date?
    var didScoreCurrentCard = false
    var batchKeys: [String] = []
    var undoSRSByID: [String: VocabularySRSState] = [:]

    func resetForReviewMode() {
        listModeEnabled = false
        reviewIndex = 0
        batchKeys = []
        resetCard(clearCardKey: true)
    }

    func resetForListMode(filter: VocabularyFilter) {
        self.filter = filter
        reviewIndex = 0
        listPageIndex = 0
        resetCard(clearCardKey: true)
    }

    func resetCard(clearCardKey: Bool) {
        contextShown = false
        answerShown = false
        if clearCardKey {
            cardKey = nil
        }
        answerShownAt = nil
        didScoreCurrentCard = false
        undoSRSByID = [:]
    }

    func reviewRecords(
        _ records: [VocabularyExportRecord]
    ) -> [VocabularyExportRecord] {
        let batchKeys = ensureBatch(records: records)
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[key(for: record)] = record
        }
        return batchKeys.compactMap { key in
            guard let record = recordsByKey[key] else { return nil }
            if isShowingCurrentCard(key: key) {
                return record
            }
            guard !isDoneForToday(record) else { return nil }
            return record
        }
    }

    @discardableResult
    func ensureBatch(
        records: [VocabularyExportRecord]
    ) -> [String] {
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[key(for: record)] = record
        }
        let remainingCurrentBatch = batchKeys.filter { key in
            guard let record = recordsByKey[key] else { return false }
            if isShowingCurrentCard(key: key) {
                return true
            }
            return !isDoneForToday(record)
        }
        if !remainingCurrentBatch.isEmpty {
            batchKeys = remainingCurrentBatch
            return remainingCurrentBatch
        }

        let nextBatch = VocabularyReviewQueueBuilder.queue(records: records, priority: priority)
            .filter { !isDoneForToday($0) }
            .prefix(10)
            .map(key(for:))
        batchKeys = Array(nextBatch)
        return batchKeys
    }

    func key(for record: VocabularyExportRecord) -> String {
        record.ids.sorted().joined(separator: "|")
    }

    func isDoneForToday(_ record: VocabularyExportRecord) -> Bool {
        guard let lastReviewedAt = record.srs.lastReviewedAt,
              Calendar.current.isDateInToday(lastReviewedAt) else { return false }
        return (record.srs.activeRecallStreak ?? 0) > 0 && record.srs.intervalDays >= 1 && !record.srs.isDue
    }

    func isShowingCurrentCard(key: String) -> Bool {
        (contextShown || answerShown) && cardKey == key
    }

    func listRecords(
        _ records: [VocabularyExportRecord],
        matching filter: VocabularyFilter
    ) -> [VocabularyExportRecord] {
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

    func listPageCount(total: Int) -> Int {
        max(1, Int(ceil(Double(total) / Double(listPageSize))))
    }

    func currentListPageRecords(
        _ records: [VocabularyExportRecord],
        matching filter: VocabularyFilter
    ) -> (records: ArraySlice<VocabularyExportRecord>, pageIndex: Int, pageCount: Int, total: Int) {
        let visibleRecords = listRecords(records, matching: filter)
        let pageCount = listPageCount(total: visibleRecords.count)
        listPageIndex = min(max(0, listPageIndex), pageCount - 1)
        let start = listPageIndex * listPageSize
        let end = min(start + listPageSize, visibleRecords.count)
        return (visibleRecords[start..<end], listPageIndex, pageCount, visibleRecords.count)
    }

    func goToPreviousListPage() -> Bool {
        guard listPageIndex > 0 else { return false }
        listPageIndex -= 1
        return true
    }

    func goToNextListPage() {
        listPageIndex += 1
    }
}
