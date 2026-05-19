import Cocoa

extension ReaderWindowController {
    func scheduleDocumentEmbeddingWarmup(priorityPageIndex: Int?) {
        guard AISettingsStore.autoEmbeddingIndexEnabled,
              EmbeddingClient.configFromCurrentAISettings() != nil else {
            return
        }
        let documentID = currentFileMD5
        scheduledEmbeddingCacheRestoreWorkItem?.cancel()
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

        scheduledEmbeddingWarmupWorkItem?.cancel()
        let warmupWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentFileMD5 == documentID else { return }
            guard self.window?.isVisible == true else {
                return
            }
            guard self.isReaderIdleForEmbedding else {
                self.embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：空闲后继续", "AI analysis data: continues when idle")
                self.embeddingStatusLabel.isHidden = false
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
}
