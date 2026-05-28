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
        let idSet = Set(ids)
        pendingPDFWordRecords = pendingPDFWordRecords.filter { !idSet.contains($0.key) }
        pendingWebWordRecords = pendingWebWordRecords.filter { !idSet.contains($0.key) }

        if currentDocumentKind == .pdf {
            let removedRecords = storedWordRecords.filter { idSet.contains($0.id) }
            guard !removedRecords.isEmpty else {
                aiPanel.removeLinkedWordBubbles(ids: ids)
                saveCurrentAIConversationBeforeDocumentChange()
                return
            }
            for record in removedRecords {
                guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
                for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                    page.removeAnnotation(annotation)
                }
            }
            storedWordRecords.removeAll { idSet.contains($0.id) }
            highlightedSelectionKeys.removeAll()
            restoreStoredWordAnnotations()
            deleteStoredWordRecords(ids: ids)
            pdfView.setNeedsDisplay(pdfView.bounds)
        } else {
            storedWebWordRecords.removeAll { idSet.contains($0.id) }
            deleteStoredWebWordRecords(ids: ids)
            restoreStoredWebWordHighlights { [weak self] in
                guard let self else { return }
                self.restoreWebAISourceUnderlines(for: self.aiPanel.activeConversationSources())
            }
        }

        aiPanel.removeLinkedWordBubbles(ids: ids)
        saveCurrentAIConversationBeforeDocumentChange()
    }
}
