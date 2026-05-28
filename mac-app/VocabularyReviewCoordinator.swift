import Cocoa

final class VocabularyReviewCoordinator {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func populate(
        container: NSView,
        records: [VocabularyExportRecord],
        filter: VocabularyFilter,
        isDark: Bool,
        autoPlayNewCard: Bool
    ) {
        removeExistingContent(from: container)
        guard let selection = VocabularyReviewCardSelector.selection(records: records, session: owner.vocabularyReviewSession) else {
            addEmptyState(to: container, filter: filter, isDark: isDark)
            return
        }

        let displayRecord = owner.vocabularyRecordWithDictionaryMetadata(selection.record)
        owner.prepareVocabularyReviewTiming(for: displayRecord, autoPlay: autoPlayNewCard)
        owner.updateVocabularySummaryWithProgress(position: selection.position, total: selection.total)
        addReviewCard(
            to: container,
            record: displayRecord,
            position: selection.position,
            total: selection.total
        )
    }

    private func removeExistingContent(from container: NSView) {
        for view in container.subviews {
            view.removeFromSuperview()
        }
    }

    private func addEmptyState(to container: NSView, filter: VocabularyFilter, isDark: Bool) {
        let empty = owner.emptyVocabularyState(filter: filter, isDark: isDark)
        container.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    private func addReviewCard(
        to container: NSView,
        record: VocabularyExportRecord,
        position: Int,
        total: Int
    ) {
        let session = owner.vocabularyReviewSession
        let card = VocabularyReviewCardBuilder(owner: owner).build(
            record: record,
            position: position,
            total: total,
            contextShown: session.contextShown,
            answerShown: session.answerShown,
            didScore: session.didScoreCurrentCard,
            canUndoScore: !session.undoSRSByID.isEmpty
        )
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
