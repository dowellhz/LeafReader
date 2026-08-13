import Cocoa

extension ReaderWindowController {
    enum EmbeddingControlState: String {
        case paused
        case cancelled
    }

    func scheduleDocumentEmbeddingWarmup(priorityPageIndex: Int?) {
        guard AISettingsStore.autoEmbeddingIndexEnabled,
              EmbeddingClient.configFromCurrentAISettings() != nil else {
            return
        }
        guard let documentID = currentFileMD5 else { return }
        cancelScheduledEmbeddingWarmup()
        if applyStoredEmbeddingControlStateIfNeeded(documentID: documentID) {
            return
        }
        let cacheWorkItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            guard self.currentFileMD5 == documentID,
                  self.window?.isVisible == true else {
                return
            }
            self.ensureDocumentAgentIndexAsync { [weak self] in
                guard let self, self.currentFileMD5 == documentID else { return }
                self.applyCachedEmbeddingsIfPossible {
                    if self.embeddingIndexIsComplete {
                        self.scheduledEmbeddingWarmupWorkItem?.cancel()
                        self.scheduledEmbeddingWarmupWorkItem = nil
                    }
                }
            }
        }
        scheduledEmbeddingCacheRestoreWorkItem = cacheWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + EmbeddingWarmupPolicy.cacheRestoreDelay, execute: cacheWorkItem)

        let warmupWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentFileMD5 == documentID else { return }
            guard self.window?.isVisible == true else {
                return
            }
            guard self.isReaderIdleForEmbedding else {
                self.showEmbeddingStatus(AppText.localized("AI 分析数据：空闲后继续", "AI analysis data: continues when idle"))
                self.scheduleDocumentEmbeddingWarmup(priorityPageIndex: priorityPageIndex)
                return
            }
            self.ensureDocumentAgentIndexAsync { [weak self] in
                guard let self, self.currentFileMD5 == documentID else { return }
                self.applyCachedEmbeddingsIfPossible {
                    guard !self.embeddingIndexIsComplete else {
                        self.scheduledEmbeddingWarmupWorkItem = nil
                        return
                    }
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: priorityPageIndex)
                }
            }
        }
        scheduledEmbeddingWarmupWorkItem = warmupWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + EmbeddingWarmupPolicy.warmupDelay, execute: warmupWorkItem)
    }

    var isReaderIdleForEmbedding: Bool {
        EmbeddingWarmupPolicy.isReaderIdle(lastInteractionAt: lastReaderInteractionAt)
    }

    func markReaderInteraction() {
        lastReaderInteractionAt = Date()
        pdfTextSnapshotCancellationToken?.deferWork(for: 0.25)
        documentAgentIndexCancellationToken?.deferWork(for: 0.25)
    }

    func cancelScheduledEmbeddingWarmup() {
        scheduledEmbeddingCacheRestoreWorkItem?.cancel()
        scheduledEmbeddingCacheRestoreWorkItem = nil
        scheduledEmbeddingWarmupWorkItem?.cancel()
        scheduledEmbeddingWarmupWorkItem = nil
    }

    func resetEmbeddingStateForDocumentChange() {
        cancelDocumentAgentPrompt()
        invalidateEmbeddingBackfill(clearPendingCallbacks: true, clearRetry: true)
        cancelScheduledEmbeddingWarmup()
        clearEmbeddingStatus()
    }

    func beginEmbeddingBackfill() {
        isPreparingPDFEmbeddings = true
        isEmbeddingBackfillPaused = false
        embeddingBackfillNeedsRetry = false
        embeddingBackfillGeneration += 1
    }

    func stopEmbeddingBackfill(clearPendingCallbacks: Bool = false) {
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        queuedEmbeddingPriorityPageIndex = nil
        if clearPendingCallbacks {
            pendingEmbeddingReadyCallbacks.removeAll()
        }
    }

    func invalidateEmbeddingBackfill(clearPendingCallbacks: Bool = false, clearRetry: Bool = false) {
        embeddingBackfillGeneration += 1
        stopEmbeddingBackfill(clearPendingCallbacks: clearPendingCallbacks)
        if clearRetry {
            embeddingBackfillNeedsRetry = false
        }
    }

    func storedEmbeddingControlState(documentID: String) -> EmbeddingControlState? {
        guard let rawValue = UserDefaults.standard.string(forKey: embeddingControlStateKey(documentID: documentID)) else {
            return nil
        }
        return EmbeddingControlState(rawValue: rawValue)
    }

    func saveEmbeddingControlState(_ state: EmbeddingControlState, documentID: String) {
        UserDefaults.standard.set(state.rawValue, forKey: embeddingControlStateKey(documentID: documentID))
    }

    func clearStoredEmbeddingControlState(documentID: String) {
        UserDefaults.standard.removeObject(forKey: embeddingControlStateKey(documentID: documentID))
    }

    func embeddingControlStateKey(documentID: String) -> String {
        "\(Self.embeddingControlStateDefaultsKey).\(documentID)"
    }

    func showPausedEmbeddingStatus() {
        showEmbeddingStatus(AppText.localized("AI 分析数据：已暂停，点击继续", "AI analysis data: paused, tap resume"))
        updateEmbeddingControlButtons()
    }

    func applyStoredEmbeddingControlStateIfNeeded(documentID: String) -> Bool {
        switch storedEmbeddingControlState(documentID: documentID) {
        case .paused:
            isPreparingPDFEmbeddings = true
            isEmbeddingBackfillPaused = true
            embeddingBackfillNeedsRetry = false
            showPausedEmbeddingStatus()
            return true
        case .cancelled:
            invalidateEmbeddingBackfill(clearPendingCallbacks: true, clearRetry: true)
            clearEmbeddingStatus()
            return true
        case nil:
            return false
        }
    }
}
