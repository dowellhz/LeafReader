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
            return currentPDFSelectionSourceLocation(pageIndex: pageIndex)
        }

        let index = currentEmbeddingPriorityIndex() ?? 0
        let selectedText = currentWebSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = AIConversationSourceLocation(
            kind: .webProgress,
            index: index,
            progress: min(1, max(0, webScrollProgress)),
            selectedText: selectedText.isEmpty ? nil : selectedText,
            webContext: currentWebSelectionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !selectedText.isEmpty {
            addAISourceUnderline(for: source)
        }
        return source
    }

    func jumpToAIConversationSource(_ source: AIConversationSourceLocation) {
        ensureAIConversationSourceBubbleLoaded(source)
        switch source.kind {
        case .pdfPage:
            addAISourceUnderline(for: source)
            if currentPageIndex() == source.index {
                updatePageLabel()
                return
            }
            jumpToPDFPage(index: source.index, skipIfCurrentPage: false)
        case .webProgress:
            jumpToWebDocumentProgress(source.progress)
        }
    }

    func jumpToWebDocumentProgress(_ progressValue: Double?) {
        let progress = min(1, max(0, progressValue ?? webScrollProgress))
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
        updatePageLabelTextColor()
        let script = """
        (() => {
          const progress = \(progress);
          const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          window.scrollTo({ top: scrollHeight * progress, behavior: 'smooth' });
        })();
        """
        webView.evaluateJavaScript(script)
        saveWebProgress()
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
        guard let loadedAIConversation, !loadedAIConversation.bubbles.isEmpty else {
            return visibleConversation
        }

        var mergedBubbles = loadedAIConversation.bubbles
        var existingKeys = Set(mergedBubbles.map(conversationBubbleKey))
        for bubble in visibleConversation.bubbles where !existingKeys.contains(conversationBubbleKey(bubble)) {
            mergedBubbles.append(bubble)
            existingKeys.insert(conversationBubbleKey(bubble))
        }
        if mergedBubbles.count > AIChatPanel.maxSavedConversationBubbles {
            mergedBubbles = Array(mergedBubbles.suffix(AIChatPanel.maxSavedConversationBubbles))
        }
        return SavedAIConversation(bubbles: mergedBubbles)
    }

    private func conversationBubbleKey(_ bubble: SavedAIConversationBubble) -> String {
        "\(bubble.role)\u{1F}\(bubble.text)"
    }
}
