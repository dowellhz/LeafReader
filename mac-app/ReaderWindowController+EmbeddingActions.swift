import Cocoa

extension ReaderWindowController {
    @objc func toggleEmbeddingBackfillPaused() {
        guard isPreparingPDFEmbeddings else { return }
        isEmbeddingBackfillPaused.toggle()
        updateEmbeddingControlButtons()
        if isEmbeddingBackfillPaused {
            embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：已暂停，点击继续", "AI analysis data: paused, tap resume")
            embeddingStatusLabel.isHidden = false
            return
        }
        guard let documentID = currentFileMD5,
              let config = EmbeddingClient.configFromCurrentAISettings() else { return }
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
        embeddingBackfillGeneration += 1
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        queuedEmbeddingPriorityPageIndex = nil
        notifyEmbeddingReady(nil, includePending: true)
        embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：已取消", "AI analysis data: cancelled")
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isPreparingPDFEmbeddings else { return }
            self.clearEmbeddingStatus()
        }
    }

    func startCurrentVectorIndex() {
        guard EmbeddingClient.configFromCurrentAISettings() != nil else {
            embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：请先配置向量模型", "AI analysis data: configure embedding model first")
            embeddingStatusLabel.isHidden = false
            return
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
        embeddingBackfillGeneration += 1
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        queuedEmbeddingPriorityPageIndex = nil
        pendingEmbeddingReadyCallbacks.removeAll()
        embeddingStoreQueue.async { [weak self] in
            self?.pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        }
        pdfAgentIndex = nil
        documentAgentIndexGeneration += 1
        isBuildingDocumentAgentIndex = false
        pendingDocumentAgentIndexCallbacks.removeAll()
        ensureDocumentAgentIndexAsync()
        embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：已清除当前书", "AI analysis data: current book cleared")
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isPreparingPDFEmbeddings else { return }
            self.clearEmbeddingStatus()
        }
    }
}
