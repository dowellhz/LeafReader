import Cocoa

extension ReaderWindowController {
    func reloadVocabularyPanelContent() {
        guard let panel = vocabularyPanelController.panel,
              let root = panel.contentView else { return }
        let filter = selectedVocabularyListFilter(in: root)
        let isDark = ReaderTheme.selected == .dark
        refreshVocabularyListContent(in: root, filter: filter)
        refreshVocabularyStats(in: root, records: currentVocabularyExportRecords)
        if !vocabularyReviewSession.listModeEnabled,
           let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: filter, isDark: isDark, autoPlayNewCard: !vocabularyReviewSession.listModeEnabled)
        }
    }

    func scheduleVocabularyPanelReload() {
        vocabularyPanelController.scheduleReload()
    }

    func refreshVocabularyStats(in root: NSView, records: [VocabularyExportRecord]) {
        let stats = VocabularyLearningStatsCalculator.stats(records: records)
        for item in VocabularyLearningStatsPresenter.items(for: stats) {
            vocabularyStatValue(item.valueIdentifier, in: root)?.stringValue = item.value
        }
    }

    private func vocabularyStatValue(_ identifier: String, in root: NSView) -> NSTextField? {
        findView(identifier: identifier, in: root) as? NSTextField
    }
}
