import Cocoa

extension ReaderWindowController {
    func prepareVocabularyReviewTiming(for record: VocabularyExportRecord, autoPlay: Bool = true) {
        let key = vocabularyReviewKey(for: record)
        guard vocabularyReviewCardKey != key else { return }
        vocabularyReviewCardKey = key
        vocabularyReviewCardShownAt = Date()
        vocabularyReviewAnswerShownAt = nil
        vocabularyReviewDidScoreCurrentCard = false
        vocabularyReviewUndoSRSByID = [:]
        if autoPlay {
            autoPlayVocabularyWordIfNeeded(record.word)
        }
    }

    func vocabularyReviewKey(for record: VocabularyExportRecord) -> String {
        record.ids.sorted().joined(separator: "|")
    }

    func scoreCurrentVocabularyCardIfNeeded(grade: Int) {
        guard !vocabularyReviewDidScoreCurrentCard else { return }
        let visibleRecords = vocabularyReviewRecords(currentVocabularyExportRecords)
        let record: VocabularyExportRecord?
        if let key = vocabularyReviewCardKey {
            record = visibleRecords.first { vocabularyReviewKey(for: $0) == key }
        } else if visibleRecords.indices.contains(vocabularyReviewIndex) {
            record = visibleRecords[vocabularyReviewIndex]
        } else {
            record = nil
        }
        guard let record else { return }
        vocabularyReviewUndoSRSByID = vocabularySRSSnapshot(ids: record.ids)
        vocabularyReviewDidScoreCurrentCard = true
        updateVocabularySRS(ids: record.ids, grade: grade)
    }

    @objc func rememberedVocabularyCard(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        scoreCurrentVocabularyCardIfNeeded(grade: 3)
        vocabularyReviewContextShown = false
        vocabularyReviewAnswerShown = true
        vocabularyReviewAnswerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        reloadVocabularyPanelContent()
    }

    @objc func rememberedAfterContextVocabularyCard(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        scoreCurrentVocabularyCardIfNeeded(grade: 2)
        vocabularyReviewUndoSRSByID = [:]
        vocabularyReviewContextShown = false
        vocabularyReviewAnswerShown = true
        vocabularyReviewAnswerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        reloadVocabularyPanelContent()
    }

    @objc func showVocabularyContext(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        vocabularyReviewContextShown = true
        vocabularyReviewAnswerShown = false
        if let currentRecord {
            autoPlayVocabularyContextIfNeeded(record: currentRecord)
        }
        reloadVocabularyPanelContent()
    }

    @objc func showVocabularyAnswer(_ sender: NSButton) {
        let currentRecord = currentVocabularyReviewRecord()
        vocabularyReviewContextShown = false
        vocabularyReviewAnswerShown = true
        vocabularyReviewAnswerShownAt = Date()
        if let currentRecord {
            autoPlayVocabularyAnswerIfNeeded(record: currentRecord)
        }
        reloadVocabularyPanelContent()
    }

    func currentVocabularyReviewRecord() -> VocabularyExportRecord? {
        let visibleRecords = vocabularyReviewRecords(currentVocabularyExportRecords)
        if let key = vocabularyReviewCardKey,
           let record = visibleRecords.first(where: { vocabularyReviewKey(for: $0) == key }) {
            return record
        }
        guard visibleRecords.indices.contains(vocabularyReviewIndex) else { return nil }
        return visibleRecords[vocabularyReviewIndex]
    }

    @objc func nextVocabularyReviewCard(_ sender: NSButton) {
        moveToNextVocabularyCard()
    }

    @objc func undoVocabularyReviewScore(_ sender: NSButton) {
        guard !vocabularyReviewUndoSRSByID.isEmpty else { return }
        let currentKey = vocabularyReviewCardKey
        restoreVocabularySRS(snapshot: vocabularyReviewUndoSRSByID)
        if let currentKey {
            vocabularyReviewBatchKeys.removeAll { $0 == currentKey }
            vocabularyReviewBatchKeys.append(currentKey)
        }
        resetVocabularyReviewCardState(clearCardKey: true)
        reloadVocabularyPanelContent()
    }

    func commitPendingVocabularyAnswerIfNeeded() {
        guard vocabularyReviewAnswerShown, !vocabularyReviewDidScoreCurrentCard else { return }
        scoreCurrentVocabularyCardIfNeeded(grade: 1)
    }

    func moveToNextVocabularyCard() {
        let currentKey = vocabularyReviewCardKey
        commitPendingVocabularyAnswerIfNeeded()
        let visibleCount = vocabularyReviewRecords(currentVocabularyExportRecords).count
        guard visibleCount > 0 else { return }
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in currentVocabularyExportRecords {
            recordsByKey[vocabularyReviewKey(for: record)] = record
        }
        if let currentKey,
           let record = recordsByKey[currentKey],
           !vocabularyRecordIsDoneForToday(record) {
            vocabularyReviewBatchKeys.removeAll { $0 == currentKey }
            vocabularyReviewBatchKeys.append(currentKey)
        }
        vocabularyReviewIndex = min(vocabularyReviewIndex, visibleCount - 1)
        resetVocabularyReviewCardState(clearCardKey: true)
        reloadVocabularyPanelContent()
    }

    func resetVocabularyReviewCardState(clearCardKey: Bool) {
        vocabularyReviewContextShown = false
        vocabularyReviewAnswerShown = false
        if clearCardKey {
            vocabularyReviewCardKey = nil
        }
        vocabularyReviewAnswerShownAt = nil
        vocabularyReviewDidScoreCurrentCard = false
        vocabularyReviewUndoSRSByID = [:]
    }

    func vocabularySRSSnapshot(ids: [String]) -> [String: VocabularySRSState] {
        let idSet = Set(ids)
        if currentDocumentKind == .pdf {
            var snapshot: [String: VocabularySRSState] = [:]
            for record in storedWordRecords where idSet.contains(record.id) {
                snapshot[record.id] = record.srs ?? VocabularySRSState.initial(createdAt: record.createdAt)
            }
            return snapshot
        }
        var snapshot: [String: VocabularySRSState] = [:]
        for record in storedWebWordRecords where idSet.contains(record.id) {
            snapshot[record.id] = record.srs ?? VocabularySRSState.initial(createdAt: record.createdAt)
        }
        return snapshot
    }

    func restoreVocabularySRS(snapshot: [String: VocabularySRSState]) {
        let idSet = Set(snapshot.keys)
        if currentDocumentKind == .pdf {
            for index in storedWordRecords.indices where idSet.contains(storedWordRecords[index].id) {
                storedWordRecords[index].srs = snapshot[storedWordRecords[index].id]
                saveStoredWordRecord(storedWordRecords[index])
            }
        } else {
            for index in storedWebWordRecords.indices where idSet.contains(storedWebWordRecords[index].id) {
                storedWebWordRecords[index].srs = snapshot[storedWebWordRecords[index].id]
                saveStoredWebWordRecord(storedWebWordRecords[index])
            }
        }

        for index in currentVocabularyExportRecords.indices where !Set(currentVocabularyExportRecords[index].ids).isDisjoint(with: idSet) {
            let old = currentVocabularyExportRecords[index]
            let restoredSRS = old.ids.compactMap { snapshot[$0] }.min { $0.dueDate < $1.dueDate } ?? old.srs
            currentVocabularyExportRecords[index] = VocabularyExportRecord(
                ids: old.ids,
                word: old.word,
                answer: old.answer,
                location: old.location,
                context: old.context,
                createdAt: old.createdAt,
                srs: restoredSRS
            )
        }
    }

    func updateVocabularySRS(ids: [String], grade: Int) {
        let idSet = Set(ids)
        if currentDocumentKind == .pdf {
            for index in storedWordRecords.indices where idSet.contains(storedWordRecords[index].id) {
                let current = storedWordRecords[index].srs ?? VocabularySRSState.initial(createdAt: storedWordRecords[index].createdAt)
                storedWordRecords[index].srs = current.reviewed(grade: grade)
                saveStoredWordRecord(storedWordRecords[index])
            }
        } else {
            for index in storedWebWordRecords.indices where idSet.contains(storedWebWordRecords[index].id) {
                let current = storedWebWordRecords[index].srs ?? VocabularySRSState.initial(createdAt: storedWebWordRecords[index].createdAt)
                storedWebWordRecords[index].srs = current.reviewed(grade: grade)
                saveStoredWebWordRecord(storedWebWordRecords[index])
            }
        }

        if let index = currentVocabularyExportRecords.firstIndex(where: { !Set($0.ids).isDisjoint(with: idSet) }) {
            let old = currentVocabularyExportRecords[index]
            currentVocabularyExportRecords[index] = VocabularyExportRecord(
                ids: old.ids,
                word: old.word,
                answer: old.answer,
                location: old.location,
                context: old.context,
                createdAt: old.createdAt,
                srs: vocabularySRSState(ids: old.ids, fallback: old.srs)
            )
        }
    }

    func vocabularySRSState(ids: [String], fallback: VocabularySRSState) -> VocabularySRSState {
        let idSet = Set(ids)
        let states: [VocabularySRSState]
        if currentDocumentKind == .pdf {
            states = storedWordRecords
                .filter { idSet.contains($0.id) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        } else {
            states = storedWebWordRecords
                .filter { idSet.contains($0.id) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        }
        return states.min { $0.dueDate < $1.dueDate } ?? fallback
    }
}
