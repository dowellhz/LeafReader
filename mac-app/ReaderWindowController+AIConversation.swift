import Foundation

extension ReaderWindowController {
    func loadSavedAIConversationIfNeeded() {
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore else {
            return
        }
        aiPanel.loadSavedConversation(store.load())
    }

    func saveAIConversationIfNeeded(_ conversation: SavedAIConversation) {
        guard AISettingsStore.saveAIConversationEnabled,
              aiConversationStore != nil else {
            return
        }
        pendingAIConversationToSave = conversation
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
        pendingAIConversationToSave = nil
        store.save(aiPanel.savedConversation())
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
        store.save(conversation)
    }

    func applyAIConversationPersistenceSetting() {
        guard let store = aiConversationStore else { return }
        if AISettingsStore.saveAIConversationEnabled {
            flushPendingAIConversationSave()
            store.save(aiPanel.savedConversation())
        } else {
            aiConversationSaveTask.cancel()
            pendingAIConversationToSave = nil
            store.clear()
        }
    }

    func currentAIConversationSourceLocation() -> AIConversationSourceLocation? {
        if currentDocumentKind == .pdf {
            guard let pageIndex = currentPageIndex() else { return nil }
            return AIConversationSourceLocation(kind: .pdfPage, index: pageIndex, progress: nil)
        }

        let index = currentEmbeddingPriorityIndex() ?? 0
        return AIConversationSourceLocation(
            kind: .webProgress,
            index: index,
            progress: min(1, max(0, webScrollProgress))
        )
    }

    func jumpToAIConversationSource(_ source: AIConversationSourceLocation) {
        switch source.kind {
        case .pdfPage:
            jumpToPDFPage(index: source.index, skipIfCurrentPage: true)
        case .webProgress:
            jumpToWebDocumentProgress(source.progress)
        }
    }

    func jumpToWebDocumentProgress(_ progressValue: Double?) {
        let progress = min(1, max(0, progressValue ?? webScrollProgress))
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
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
}
