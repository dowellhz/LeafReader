import Cocoa

extension ReaderWindowController {
    func reloadVocabularyPanelContent() {
        guard let panel = vocabularyPanelController.panel,
              let root = panel.contentView else { return }
        let filter = selectedVocabularyListFilter(in: root)
        let isDark = ReaderTheme.selected == .dark
        refreshVocabularyListContent(in: root, filter: filter)
        if !vocabularyReviewSession.listModeEnabled,
           let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: filter, isDark: isDark, autoPlayNewCard: !vocabularyReviewSession.listModeEnabled)
        }
    }

    func scheduleVocabularyPanelReload() {
        vocabularyPanelController.scheduleReload()
    }
}
