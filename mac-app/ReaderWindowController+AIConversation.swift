import Foundation

extension ReaderWindowController {
    func loadSavedAIConversationIfNeeded() {
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore else {
            return
        }
        let conversation = store.load()
        loadedAIConversation = conversation
        aiPanel.loadSavedConversation(conversation)
        restoreSavedAISourceUnderlines(from: conversation)
    }

    func saveAIConversationIfNeeded(_ conversation: SavedAIConversation) {
        guard AISettingsStore.saveAIConversationEnabled,
              aiConversationStore != nil else {
            return
        }
        pendingAIConversationToSave = mergedAIConversationForSave(conversation)
        aiConversationSaveTask.schedule { [weak self] in
            self?.flushPendingAIConversationSave()
        }
    }

    func saveCurrentAIConversationBeforeDocumentChange() {
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore else {
            return
        }
        aiConversationSaveTask.cancel()
        let conversation = mergedAIConversationForSave(aiPanel.savedConversation())
        pendingAIConversationToSave = nil
        loadedAIConversation = conversation
        store.save(conversation)
    }

    func flushPendingAIConversationSave() {
        aiConversationSaveTask.cancel()
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore,
              let conversation = pendingAIConversationToSave else {
            pendingAIConversationToSave = nil
            return
        }
        pendingAIConversationToSave = nil
        loadedAIConversation = conversation
        store.save(conversation)
    }

    func removeAIConversationBubblesFromPersistence(_ deletedBubbles: [SavedAIConversationBubble]) {
        guard AISettingsStore.saveAIConversationEnabled,
              !deletedBubbles.isEmpty else {
            return
        }
        if loadedAIConversation == nil {
            loadedAIConversation = aiConversationStore?.load()
        }
        loadedAIConversation = loadedAIConversation?.removing(deletedBubbles)
        pendingAIConversationToSave = pendingAIConversationToSave?.removing(deletedBubbles)
    }

    func applyAIConversationPersistenceSetting() {
        guard let store = aiConversationStore else { return }
        if AISettingsStore.saveAIConversationEnabled {
            flushPendingAIConversationSave()
            let conversation = mergedAIConversationForSave(aiPanel.savedConversation())
            loadedAIConversation = conversation
            store.save(conversation)
        } else {
            aiConversationSaveTask.cancel()
            pendingAIConversationToSave = nil
            loadedAIConversation = nil
            store.clear()
            clearAISourceUnderlines()
        }
    }

    func currentAIConversationSourceLocation() -> AIConversationSourceLocation? {
        if currentDocumentKind == .pdf {
            guard let pageIndex = currentPageIndex() else { return nil }
            let focusedSelection = currentFocusedSelectionForAI()
            switch focusedSelection?.origin {
            case .explicitSelection:
                return currentPDFSelectionSourceLocation(pageIndex: pageIndex)
                    ?? AIConversationSourceLocation(kind: .pdfPage, index: pageIndex, progress: nil, selectedText: focusedSelection?.text)
            case .readAloudSegment:
                return currentPDFReadAloudSourceLocation(pageIndex: pageIndex)
                    ?? AIConversationSourceLocation(kind: .pdfPage, index: pageIndex, progress: nil, selectedText: focusedSelection?.text)
            case nil:
                return AIConversationSourceLocation(kind: .pdfPage, index: pageIndex, progress: nil)
            }
        }

        let index = currentEmbeddingPriorityIndex() ?? 0
        let focusedSelection = currentFocusedSelectionForAI()
        let selectedText = focusedSelection?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isExplicitSelection = focusedSelection?.origin == .explicitSelection
        let source = AIConversationSourceLocation(
            kind: .webProgress,
            index: index,
            progress: min(1, max(0, webScrollProgress)),
            selectedText: selectedText.isEmpty ? nil : selectedText,
            webContext: focusedSelection?.context.trimmingCharacters(in: .whitespacesAndNewlines),
            occurrenceIndex: isExplicitSelection ? currentWebSelectionOccurrenceIndex : nil
        )
        if isExplicitSelection, !selectedText.isEmpty {
            addAISourceUnderline(for: source)
        }
        return source
    }

    func jumpToAIConversationSource(_ source: AIConversationSourceLocation) {
        ensureAIConversationSourceBubbleLoaded(source)
        switch source.kind {
        case .pdfPage:
            addAISourceUnderline(for: source)
            jumpToPDFPage(index: source.index, skipIfCurrentPage: false)
        case .webProgress:
            jumpToWebDocumentProgress(source.progress)
        }
    }

    func jumpToWebDocumentProgress(_ progressValue: Double?) {
        jumpToWebProgress(progressValue ?? webScrollProgress, animated: true)
    }

    @discardableResult
    func ensureAIConversationSourceBubbleLoaded(_ source: AIConversationSourceLocation) -> Bool {
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore else {
            return aiPanel.hasConversationSourceBubble(source)
        }
        let conversation = loadedAIConversation ?? store.load()
        loadedAIConversation = conversation
        return aiPanel.appendSavedConversationBubbles(for: source, from: conversation)
    }

    func mergedAIConversationForSave(_ visibleConversation: SavedAIConversation) -> SavedAIConversation {
        SavedAIConversation.mergedForSave(
            loaded: loadedAIConversation,
            visible: visibleConversation,
            maxBubbles: AIChatPanel.maxSavedConversationBubbles
        )
    }
}
