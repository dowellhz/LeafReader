import Cocoa

extension ReaderWindowController {
    func vocabularyRecords(_ records: [VocabularyExportRecord], matching filter: VocabularyFilter) -> [VocabularyExportRecord] {
        vocabularyReviewSession.listRecords(records, matching: filter)
    }

    func vocabularyReviewRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        vocabularyReviewSession.reviewRecords(records)
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
        guard let root = vocabularyPanelController.rootView,
              let summary = findView(identifier: "vocabularySummaryLabel", in: root) as? NSTextField else { return }
        summary.stringValue = "\(vocabularySummaryText(records: currentVocabularyExportRecords, filter: vocabularyReviewSession.filter)) · \(position) / \(total)"
    }
}
