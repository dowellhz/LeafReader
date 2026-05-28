import Foundation

struct VocabularyReviewCardSelection {
    let record: VocabularyExportRecord
    let position: Int
    let total: Int
}

enum VocabularyReviewCardSelector {
    static func selection(
        records: [VocabularyExportRecord],
        session: VocabularyReviewSession
    ) -> VocabularyReviewCardSelection? {
        let visibleRecords = session.reviewRecords(records)
        if (session.contextShown || session.answerShown),
           let key = session.cardKey,
           let preservedRecord = records.first(where: { session.key(for: $0) == key }) {
            let selectedPosition = visibleRecords.firstIndex(where: { session.key(for: $0) == key })
                .map { $0 + 1 }
                ?? min(session.reviewIndex + 1, max(1, visibleRecords.count))
            return VocabularyReviewCardSelection(
                record: preservedRecord,
                position: selectedPosition,
                total: max(visibleRecords.count, selectedPosition)
            )
        }

        guard !visibleRecords.isEmpty else { return nil }
        session.reviewIndex = min(max(0, session.reviewIndex), visibleRecords.count - 1)
        if (session.contextShown || session.answerShown),
           let key = session.cardKey,
           let preservedIndex = visibleRecords.firstIndex(where: { session.key(for: $0) == key }) {
            session.reviewIndex = preservedIndex
            return VocabularyReviewCardSelection(
                record: visibleRecords[preservedIndex],
                position: preservedIndex + 1,
                total: visibleRecords.count
            )
        }

        return VocabularyReviewCardSelection(
            record: visibleRecords[session.reviewIndex],
            position: session.reviewIndex + 1,
            total: visibleRecords.count
        )
    }
}
