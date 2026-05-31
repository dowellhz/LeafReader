import Cocoa

extension ReaderWindowController {
    @objc func markVocabularyRecordMastered(_ sender: NSButton) {
        let ids = sender.identifier?.rawValue
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        guard !ids.isEmpty else { return }
        removeVocabularyRecords(ids: ids)
        if let card = sender.superview,
           let stack = card.superview as? NSStackView {
            stack.removeArrangedSubview(card)
            card.removeFromSuperview()
        }
        currentVocabularyExportRecords.removeAll { record in
            !Set(record.ids).isDisjoint(with: ids)
        }
        if currentVocabularyExportRecords.isEmpty,
           vocabularyPanelController.panel != nil {
            closeVocabularyPanel()
        } else {
            vocabularyReviewSession.reviewIndex = min(vocabularyReviewSession.reviewIndex, max(0, vocabularyReviewRecords(currentVocabularyExportRecords).count - 1))
            vocabularyReviewSession.answerShown = false
            scheduleVocabularyPanelReload()
        }
    }

    func removeVocabularyRecords(ids: [String]) {
        let idSet = expandedVocabularyRecordIDs(for: Set(ids))
        guard !idSet.isEmpty else { return }
        let idsToRemove = Array(idSet)

        pendingPDFWordRecords = pendingPDFWordRecords.filter { !idSet.contains($0.key) }
        pendingWebWordRecords = pendingWebWordRecords.filter { !idSet.contains($0.key) }

        if currentDocumentKind == .pdf {
            let removedRecords = storedWordRecords.filter { idSet.contains($0.id) }
            for record in removedRecords {
                guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
                for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                    page.removeAnnotation(annotation)
                }
            }
            if !removedRecords.isEmpty {
                storedWordRecords.removeAll { idSet.contains($0.id) }
                highlightedSelectionKeys.removeAll()
                restoreStoredWordAnnotations()
            }
            deleteStoredWordRecords(ids: idsToRemove)
            pdfView.setNeedsDisplay(pdfView.bounds)
        } else {
            let didRemoveWebRecords = storedWebWordRecords.contains { idSet.contains($0.id) }
            if didRemoveWebRecords {
                storedWebWordRecords.removeAll { idSet.contains($0.id) }
            }
            deleteStoredWebWordRecords(ids: idsToRemove)
            if didRemoveWebRecords {
                restoreStoredWebWordHighlights { [weak self] in
                    guard let self else { return }
                    self.restoreWebAISourceUnderlines(for: self.aiPanel.activeConversationSources())
                }
            }
        }

        aiPanel.removeLinkedWordBubbles(ids: idsToRemove)
        saveCurrentAIConversationBeforeDocumentChange()
    }

    private func expandedVocabularyRecordIDs(for ids: Set<String>) -> Set<String> {
        if currentDocumentKind == .pdf {
            return VocabularyRecordDeletionPlanner.expandedIDs(
                requestedIDs: ids,
                storedRecords: storedWordRecords.map { VocabularyDeletionRecord(id: $0.id, word: $0.word) },
                pendingRecords: pendingPDFWordRecords.values.map { VocabularyDeletionRecord(id: $0.id, word: $0.word) }
            )
        }
        return VocabularyRecordDeletionPlanner.expandedIDs(
            requestedIDs: ids,
            storedRecords: storedWebWordRecords.map { VocabularyDeletionRecord(id: $0.id, word: $0.word) },
            pendingRecords: pendingWebWordRecords.values.map { VocabularyDeletionRecord(id: $0.id, word: $0.word) }
        )
    }
}
