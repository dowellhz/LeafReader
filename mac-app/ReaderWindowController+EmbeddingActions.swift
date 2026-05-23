import Cocoa

extension ReaderWindowController {
    @objc func toggleEmbeddingBackfillPaused() {
        guard isPreparingPDFEmbeddings else { return }
        isEmbeddingBackfillPaused.toggle()
        updateEmbeddingControlButtons()
        if isEmbeddingBackfillPaused {
            if let documentID = currentFileMD5 {
                saveEmbeddingControlState(.paused, documentID: documentID)
            }
            showPausedEmbeddingStatus()
            return
        }
        guard let documentID = currentFileMD5,
              let config = EmbeddingClient.configFromCurrentAISettings() else { return }
        clearStoredEmbeddingControlState(documentID: documentID)
        continuePDFEmbeddingBackfill(
            documentID: documentID,
            config: config,
            priorityPageIndex: queuedEmbeddingPriorityPageIndex,
            afterFirstBatch: nil,
            notifyPendingAfterBatch: true,
            generation: embeddingBackfillGeneration
        )
    }

    @objc func cancelEmbeddingBackfill() {
        guard isPreparingPDFEmbeddings else { return }
        if let documentID = currentFileMD5 {
            saveEmbeddingControlState(.cancelled, documentID: documentID)
        }
        invalidateEmbeddingBackfill()
        notifyEmbeddingReady(nil, includePending: true)
        clearEmbeddingStatus()
    }

    func startCurrentVectorIndex() {
        guard EmbeddingClient.configFromCurrentAISettings() != nil else {
            showEmbeddingStatus(AppText.localized("AI 分析数据：请先配置向量模型", "AI analysis data: configure embedding model first"))
            return
        }
        if let documentID = currentFileMD5 {
            clearStoredEmbeddingControlState(documentID: documentID)
        }
        embeddingBackfillNeedsRetry = false
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else { return }
            self.preparePDFEmbeddingsIfPossible(priorityPageIndex: self.currentEmbeddingPriorityIndex())
        }
    }

    func clearCurrentVectorIndex() {
        guard let documentID = currentFileMD5 else {
            NSSound.beep()
            return
        }
        clearStoredEmbeddingControlState(documentID: documentID)
        invalidateEmbeddingBackfill(clearPendingCallbacks: true)
        embeddingStoreQueue.async { [weak self] in
            self?.pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        }
        invalidateDocumentAgentIndex()
        ensureDocumentAgentIndexAsync()
        showEmbeddingStatus(AppText.localized("AI 分析数据：已清除当前书", "AI analysis data: current book cleared"))
        updateEmbeddingControlButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + EmbeddingActionPolicy.statusClearDelay) { [weak self] in
            guard let self, !self.isPreparingPDFEmbeddings else { return }
            self.clearEmbeddingStatus()
        }
    }
}
