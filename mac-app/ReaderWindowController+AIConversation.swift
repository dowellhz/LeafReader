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
              let store = aiConversationStore else {
            return
        }
        store.save(conversation)
    }

    func saveCurrentAIConversationBeforeDocumentChange() {
        guard AISettingsStore.saveAIConversationEnabled,
              let store = aiConversationStore else {
            return
        }
        store.save(aiPanel.savedConversation())
    }

    func applyAIConversationPersistenceSetting() {
        guard let store = aiConversationStore else { return }
        if AISettingsStore.saveAIConversationEnabled {
            store.save(aiPanel.savedConversation())
        } else {
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
            jumpToPDFPage(index: source.index)
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
