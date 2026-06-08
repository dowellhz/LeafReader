import Cocoa

extension ReaderWindowController {
    func prepareVocabularyReviewTiming(for record: VocabularyExportRecord, autoPlay: Bool = true) {
        let key = vocabularyReviewSession.key(for: record)
        guard vocabularyReviewSession.cardKey != key else { return }
        vocabularyReviewSession.cardKey = key
        vocabularyReviewSession.cardShownAt = Date()
        vocabularyReviewSession.answerShownAt = nil
        vocabularyReviewSession.didScoreCurrentCard = false
        vocabularyReviewSession.undoSRSByID = [:]
        if autoPlay {
            autoPlayVocabularyWordIfNeeded(record.word)
        }
    }

    func scoreCurrentVocabularyCardIfNeeded(grade: Int) {
        guard !vocabularyReviewSession.didScoreCurrentCard else { return }
        let visibleRecords = vocabularyReviewRecords(currentVocabularyExportRecords)
        let record: VocabularyExportRecord?
        if let key = vocabularyReviewSession.cardKey {
            record = visibleRecords.first { vocabularyReviewSession.key(for: $0) == key }
        } else if visibleRecords.indices.contains(vocabularyReviewSession.reviewIndex) {
            record = visibleRecords[vocabularyReviewSession.reviewIndex]
        } else {
            record = nil
        }
        guard let record else { return }
        vocabularyReviewSession.undoSRSByID = vocabularySRSSnapshot(ids: record.ids)
        vocabularyReviewSession.didScoreCurrentCard = true
        updateVocabularySRS(ids: record.ids, grade: grade)
    }

    @objc func rememberedVocabularyCard(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        scoreCurrentVocabularyCardIfNeeded(grade: 3)
        vocabularyReviewSession.contextShown = false
        vocabularyReviewSession.answerShown = true
        vocabularyReviewSession.answerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        scheduleVocabularyPanelReload()
    }

    @objc func rememberedAfterContextVocabularyCard(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        scoreCurrentVocabularyCardIfNeeded(grade: 2)
        vocabularyReviewSession.undoSRSByID = [:]
        vocabularyReviewSession.contextShown = false
        vocabularyReviewSession.answerShown = true
        vocabularyReviewSession.answerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        scheduleVocabularyPanelReload()
    }

    @objc func showVocabularyContext(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        vocabularyReviewSession.contextShown = true
        vocabularyReviewSession.answerShown = false
        if let currentRecord {
            autoPlayVocabularyContextIfNeeded(record: currentRecord)
        }
        scheduleVocabularyPanelReload()
    }

    @objc func showVocabularyAnswer(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        vocabularyReviewSession.contextShown = false
        vocabularyReviewSession.answerShown = true
        vocabularyReviewSession.answerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        scheduleVocabularyPanelReload()
    }

    func currentVocabularyReviewRecord() -> VocabularyExportRecord? {
        let visibleRecords = vocabularyReviewRecords(currentVocabularyExportRecords)
        if let key = vocabularyReviewSession.cardKey,
           let record = visibleRecords.first(where: { vocabularyReviewSession.key(for: $0) == key }) {
            return record
        }
        guard visibleRecords.indices.contains(vocabularyReviewSession.reviewIndex) else { return nil }
        return visibleRecords[vocabularyReviewSession.reviewIndex]
    }

    @objc func nextVocabularyReviewCard(_ sender: NSButton) {
        moveToNextVocabularyCard()
    }

    @objc func undoVocabularyReviewScore(_ sender: NSButton) {
        guard !vocabularyReviewSession.undoSRSByID.isEmpty else { return }
        let currentKey = vocabularyReviewSession.cardKey
        restoreVocabularySRS(snapshot: vocabularyReviewSession.undoSRSByID)
        if let currentKey {
            vocabularyReviewSession.batchKeys.removeAll { $0 == currentKey }
            vocabularyReviewSession.batchKeys.append(currentKey)
        }
        resetVocabularyReviewCardState(clearCardKey: true)
        scheduleVocabularyPanelReload()
    }

    func commitPendingVocabularyAnswerIfNeeded() {
        guard vocabularyReviewSession.answerShown, !vocabularyReviewSession.didScoreCurrentCard else { return }
        scoreCurrentVocabularyCardIfNeeded(grade: 1)
    }

    func moveToNextVocabularyCard() {
        let currentKey = vocabularyReviewSession.cardKey
        commitPendingVocabularyAnswerIfNeeded()
        let visibleCount = vocabularyReviewRecords(currentVocabularyExportRecords).count
        guard visibleCount > 0 else { return }
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in currentVocabularyExportRecords {
            recordsByKey[vocabularyReviewSession.key(for: record)] = record
        }
        if let currentKey,
           let record = recordsByKey[currentKey],
           !vocabularyReviewSession.isDoneForToday(record) {
            vocabularyReviewSession.batchKeys.removeAll { $0 == currentKey }
            vocabularyReviewSession.batchKeys.append(currentKey)
        }
        vocabularyReviewSession.reviewIndex = min(vocabularyReviewSession.reviewIndex, visibleCount - 1)
        resetVocabularyReviewCardState(clearCardKey: true)
        scheduleVocabularyPanelReload()
    }

    func resetVocabularyReviewCardState(clearCardKey: Bool) {
        vocabularyReviewSession.resetCard(clearCardKey: clearCardKey)
    }

    func vocabularySRSSnapshot(ids: [String]) -> [String: VocabularySRSState] {
        VocabularyReviewScoringService.snapshot(
            ids: ids,
            documentKind: currentDocumentKind,
            pdfRecords: storedWordRecords,
            webRecords: storedWebWordRecords
        )
    }

    func restoreVocabularySRS(snapshot: [String: VocabularySRSState]) {
        VocabularyReviewScoringService.restore(
            snapshot: snapshot,
            documentKind: currentDocumentKind,
            pdfRecords: &storedWordRecords,
            webRecords: &storedWebWordRecords,
            exportRecords: &currentVocabularyExportRecords
        )
        updateStoredVocabularyRecords(
            ids: Set(snapshot.keys),
            updatePDF: { _ in true },
            updateWeb: { _ in true }
        )
    }

    func updateVocabularySRS(ids: [String], grade: Int) {
        VocabularyReviewScoringService.update(
            ids: ids,
            grade: grade,
            documentKind: currentDocumentKind,
            pdfRecords: &storedWordRecords,
            webRecords: &storedWebWordRecords,
            exportRecords: &currentVocabularyExportRecords
        )
        updateStoredVocabularyRecords(
            ids: Set(ids),
            updatePDF: { _ in true },
            updateWeb: { _ in true }
        )
    }

}
