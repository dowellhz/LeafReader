import Cocoa

extension ReaderWindowController {
    var vocabularyReviewPreferences: VocabularyReviewPreferences? {
        guard let currentFileMD5, !currentFileMD5.isEmpty else { return nil }
        return VocabularyReviewPreferences(fileID: currentFileMD5)
    }

    @objc func showVocabularyBook() {
        presentVocabularyTrainer()
    }

    func presentVocabularyTrainer() {
        let records = makeCurrentVocabularyExportRecords()
        guard !records.isEmpty else {
            NSSound.beep()
            return
        }

        currentVocabularyExportRecords = records
        vocabularyReviewSession.filter = .due
        loadVocabularyReviewPreferences()
        vocabularyReviewSession.resetForReviewMode()
        vocabularyPanelController.show(records: records)
        backfillFrequencyForCurrentTrainerIfNeeded(autoPlayAfterCompletion: false)
    }

    func makeCurrentVocabularyExportRecords() -> [VocabularyExportRecord] {
        VocabularyRecordProvider.records(
            documentKind: currentDocumentKind,
            pdfRecords: storedWordRecords,
            webRecords: storedWebWordRecords,
            pdfContext: { [weak self] in
                VocabularyContextProvider.pdfContext(for: $0, document: self?.pdfView.document)
            }
        )
    }

    func backfillFrequencyForCurrentTrainerIfNeeded(autoPlayAfterCompletion: Bool) {
        guard vocabularyReviewSession.priority == .frequencyFirst,
              let root = vocabularyPanelController.rootView else { return }
        showVocabularyFrequencyLoading(in: root)
        backfillVocabularyFrequenciesIfNeeded(progress: { [weak self, weak root] word, current, total in
            guard let self, let root else { return }
            self.updateVocabularyFrequencyLoading(in: root, word: word, current: current, total: total)
        }) { [weak self, weak root] in
            guard let self, let root else { return }
            self.showVocabularyReviewMode(in: root, autoPlay: autoPlayAfterCompletion)
        }
    }

    func loadVocabularyReviewPriorityPreference() {
        vocabularyReviewSession.priority = vocabularyReviewPreferences?.reviewPriority ?? .frequencyFirst
    }

    func loadVocabularyReviewPreferences() {
        loadVocabularyReviewPriorityPreference()
        vocabularyReviewSession.dailyReviewGoal = vocabularyReviewPreferences?.dailyReviewGoal ?? VocabularyDailyGoalPolicy.defaultGoal
    }

    func saveVocabularyReviewPriorityPreference(_ priority: VocabularyReviewPriority) {
        guard let preferences = vocabularyReviewPreferences else { return }
        preferences.reviewPriority = priority
    }

    func saveVocabularyDailyGoalPreference(_ goal: Int) {
        guard let preferences = vocabularyReviewPreferences else { return }
        preferences.dailyReviewGoal = goal
    }
}
