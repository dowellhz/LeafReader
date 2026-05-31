import Cocoa

final class ReaderAIPanelCoordinator {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func installCallbacks() {
        installResizeCallbacks()
        installContentCallbacks()
        installVocabularyCallbacks()
        installConversationCallbacks()
        installSelectionToolbarCallbacks()
    }

    private func installResizeCallbacks() {
        owner.resizeHandle.onDragDeltaX = { [weak owner] deltaX in
            owner?.resizeAIPanel(deltaX: deltaX)
        }
        owner.resizeHandle.onDragEnded = { [weak owner] in
            owner?.finishAIPanelResize()
        }
    }

    private func installContentCallbacks() {
        owner.aiPanel.onAskSelectedText = { [weak owner] text in
            guard let owner else { return nil }
            return owner.contextForCurrentSelection(selectedText: text)
        }
        owner.aiPanel.onSummarizeCurrentContent = { [weak owner] completion in
            owner?.currentSummaryContent(completion: completion)
        }
        owner.aiPanel.onTranslateCurrentContent = { [weak owner] completion in
            owner?.currentTranslationContent(completion: completion)
        }
        owner.aiPanel.onCurrentReadingContent = { [weak owner] completion in
            owner?.currentReadingQuestionContent(completion: completion)
        }
        owner.aiPanel.onDocumentQuestionPrompt = { [weak owner] request, completion in
            owner?.documentAgentPrompt(
                question: request.question,
                questionSubject: request.questionSubject,
                context: request.context,
                completion: completion
            )
        }
        owner.aiPanel.onDocumentQuestionCancelled = { [weak owner] in
            owner?.cancelDocumentAgentPrompt()
        }
        owner.aiPanel.onSettingsRequired = { [weak owner] in
            owner?.openModelSettings()
        }
    }

    private func installVocabularyCallbacks() {
        owner.aiPanel.onSelectedWordQuestionStarted = { [weak owner] request in
            guard let owner else { return nil }
            if owner.currentDocumentKind == .pdf {
                return owner.persistSelectedWordIfNeeded(
                    owner.pdfView.currentSelection,
                    text: request.text,
                    context: request.selectedContext
                )
            }
            return owner.persistSelectedWebWordIfNeeded(text: request.text, context: request.selectedContext)
        }
        owner.aiPanel.onLinkedAnswerCompleted = { [weak owner] linkID, question, answer in
            owner?.updateStoredLinkedWordAnswer(linkID: linkID, question: question, answer: answer)
        }
        owner.aiPanel.onLinkedAnswerFailed = { [weak owner] linkID in
            owner?.discardPendingLinkedWord(linkID: linkID)
        }
        owner.aiPanel.onLinkedWordAnswerAvailable = { [weak owner] linkID in
            owner?.linkedWordAnswer(for: linkID)
        }
        owner.aiPanel.onLinkedBubbleSelected = { [weak owner] linkID in
            owner?.jumpToStoredLinkedWord(linkID: linkID)
        }
        owner.aiPanel.onLinkedBubbleDeleted = { [weak owner] linkID in
            owner?.removeVocabularyRecords(ids: [linkID])
        }
    }

    private func installConversationCallbacks() {
        owner.aiPanel.onConversationChanged = { [weak owner] conversation in
            owner?.saveAIConversationIfNeeded(conversation)
        }
        owner.aiPanel.onConversationBubblesDeleted = { [weak owner] deletedBubbles in
            owner?.removeAIConversationBubblesFromPersistence(deletedBubbles)
        }
        owner.aiPanel.onConversationSourcesChanged = { [weak owner] sources in
            owner?.reconcileAISourceUnderlines(activeSources: sources)
        }
        owner.aiPanel.onCurrentSourceLocation = { [weak owner] in
            owner?.currentAIConversationSourceLocation()
        }
        owner.aiPanel.onConversationBubbleSelected = { [weak owner] sourceLocation in
            owner?.jumpToAIConversationSource(sourceLocation)
        }
        owner.aiPanel.onNonFollowUpSelectionInteraction = { [weak owner] in
            owner?.clearReaderSelectionForBubbleSelection()
        }
    }

    private func installSelectionToolbarCallbacks() {
        owner.selectionActionToolbar.onTranslate = { [weak owner] in
            owner?.runSelectionToolbarAction(.translate)
        }
        owner.selectionActionToolbar.onExplain = { [weak owner] in
            owner?.runSelectionToolbarAction(.explain)
        }
        owner.selectionActionToolbar.onAddWord = { [weak owner] in
            owner?.runSelectionToolbarAction(.addWord)
        }
        owner.selectionActionToolbar.onSummarize = { [weak owner] in
            owner?.runSelectionToolbarAction(.summarize)
        }
        owner.selectionActionToolbar.onSpeak = { [weak owner] in
            owner?.runSelectionToolbarAction(.speak)
        }
        owner.selectionActionToolbar.onNote = { [weak owner] in
            owner?.runSelectionToolbarAction(.note)
        }
        owner.selectionActionToolbar.onCopy = { [weak owner] in
            owner?.runSelectionToolbarAction(.copy)
        }
        owner.selectionActionToolbar.onConfigureModel = { [weak owner] in
            owner?.runSelectionToolbarAction(.configureModel)
        }
    }
}
