import Cocoa

extension ReaderWindowController {
    func applyCachedEmbeddingsIfPossible(completion: (() -> Void)? = nil) {
        guard let documentID = currentFileMD5,
              let index = pdfAgentIndex,
              let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion?()
            return
        }
        let chunks = index.indexableChunks
        guard !chunks.isEmpty else {
            completion?()
            return
        }
        let chunkIDs = chunks.map(\.id)
        embeddingStoreQueue.async { [weak self] in
            guard let self, let store = self.pdfEmbeddingStore else {
                DispatchQueue.main.async { completion?() }
                return
            }
            let cached = store.embeddings(documentID: documentID, model: config.cacheModelID, chunkIDs: chunkIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.currentFileMD5 == documentID,
                      EmbeddingClient.configFromCurrentAISettings()?.cacheModelID == config.cacheModelID else {
                    completion?()
                    return
                }
                self.pdfAgentIndex?.applyEmbeddings(cached)
                if !cached.isEmpty, let progress = self.pdfAgentIndex?.embeddingCoverage {
                    self.updateEmbeddingStatusForCoverage(isComplete: progress.embedded >= progress.total)
                }
                completion?()
            }
        }
    }

    var embeddingIndexIsComplete: Bool {
        guard let progress = pdfAgentIndex?.embeddingCoverage,
              progress.total > 0 else {
            return false
        }
        return progress.embedded >= progress.total
    }

    func preparePDFEmbeddingsIfPossible(priorityPageIndex: Int? = nil, completion: (() -> Void)? = nil) {
        guard let documentID = currentFileMD5,
              pdfAgentIndex != nil,
              let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion?()
            return
        }

        if isPreparingPDFEmbeddings {
            if isEmbeddingBackfillPaused {
                isEmbeddingBackfillPaused = false
                updateEmbeddingControlButtons()
                if let documentID = currentFileMD5,
                   let config = EmbeddingClient.configFromCurrentAISettings() {
                    let generation = embeddingBackfillGeneration
                    DispatchQueue.main.async { [weak self] in
                        guard let self, generation == self.embeddingBackfillGeneration else { return }
                        self.continuePDFEmbeddingBackfill(
                            documentID: documentID,
                            config: config,
                            priorityPageIndex: priorityPageIndex,
                            afterFirstBatch: nil,
                            notifyPendingAfterBatch: true,
                            generation: generation
                        )
                    }
                }
            }
            if let priorityPageIndex {
                queuedEmbeddingPriorityPageIndex = priorityPageIndex
            }
            if let completion {
                pendingEmbeddingReadyCallbacks.append(completion)
            }
            return
        }

        applyCachedEmbeddingsIfPossible { [weak self] in
            guard let self else { return }
            guard self.currentFileMD5 == documentID,
                  EmbeddingClient.configFromCurrentAISettings()?.cacheModelID == config.cacheModelID,
                  self.pdfAgentIndex != nil else {
                completion?()
                return
            }
            if self.embeddingIndexIsComplete {
                self.notifyEmbeddingReady(completion, includePending: true)
                self.updateEmbeddingStatusForCoverage(isComplete: true)
                return
            }

            self.isPreparingPDFEmbeddings = true
            self.isEmbeddingBackfillPaused = false
            self.embeddingBackfillNeedsRetry = false
            self.embeddingBackfillGeneration += 1
            let generation = self.embeddingBackfillGeneration
            self.updateEmbeddingControlButtons()
            self.continuePDFEmbeddingBackfill(
                documentID: documentID,
                config: config,
                priorityPageIndex: priorityPageIndex,
                afterFirstBatch: completion,
                notifyPendingAfterBatch: completion != nil,
                generation: generation
            )
        }
    }

    func continuePDFEmbeddingBackfill(
        documentID: String,
        config: EmbeddingModelConfig,
        priorityPageIndex: Int?,
        afterFirstBatch: (() -> Void)?,
        notifyPendingAfterBatch: Bool,
        generation: Int
    ) {
        guard generation == embeddingBackfillGeneration,
              currentFileMD5 == documentID,
              let index = pdfAgentIndex else {
            isPreparingPDFEmbeddings = false
            queuedEmbeddingPriorityPageIndex = nil
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            clearEmbeddingStatus()
            return
        }
        guard !isEmbeddingBackfillPaused else {
            embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：已暂停，点击继续", "AI analysis data: paused, tap resume")
            embeddingStatusLabel.isHidden = false
            updateEmbeddingControlButtons()
            return
        }

        let missing = index.missingEmbeddingChunks(limit: 12, preferredPageIndex: priorityPageIndex).map {
            PDFEmbeddingChunk(id: $0.id, pageIndex: $0.pageIndex, chunkIndex: $0.chunkIndex, text: $0.text)
        }
        guard !missing.isEmpty else {
            isPreparingPDFEmbeddings = false
            isEmbeddingBackfillPaused = false
            queuedEmbeddingPriorityPageIndex = nil
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            updateEmbeddingStatusForCoverage(isComplete: true)
            updateEmbeddingControlButtons()
            return
        }

        updateEmbeddingStatus(chunks: missing)
        embeddingClient.embed(texts: missing.map(\.text), config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.embeddingBackfillGeneration,
                      self.currentFileMD5 == documentID else {
                    self.isPreparingPDFEmbeddings = false
                    self.isEmbeddingBackfillPaused = false
                    self.queuedEmbeddingPriorityPageIndex = nil
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                    self.clearEmbeddingStatus()
                    self.updateEmbeddingControlButtons()
                    return
                }

                switch result {
                case .success(let embeddings):
                    var mapped: [String: [Float]] = [:]
                    for (chunk, embedding) in zip(missing, embeddings) {
                        mapped[chunk.id] = embedding
                    }
                    self.pdfAgentIndex?.applyEmbeddings(mapped)
                    let nextPriorityPageIndex = self.queuedEmbeddingPriorityPageIndex
                    self.queuedEmbeddingPriorityPageIndex = nil
                    let shouldDeferPendingCallbacks = nextPriorityPageIndex != nil && !self.pendingEmbeddingReadyCallbacks.isEmpty
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: notifyPendingAfterBatch && !shouldDeferPendingCallbacks)
                    self.updateEmbeddingStatusForCoverage(isComplete: false)
                    let shouldNotifyPendingAfterNextBatch = shouldDeferPendingCallbacks
                    self.embeddingStoreQueue.async { [weak self] in
                        self?.pdfEmbeddingStore?.save(documentID: documentID, model: config.cacheModelID, chunks: missing, embeddings: embeddings)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                            self?.continuePDFEmbeddingBackfill(
                                documentID: documentID,
                                config: config,
                                priorityPageIndex: nextPriorityPageIndex,
                                afterFirstBatch: nil,
                                notifyPendingAfterBatch: shouldNotifyPendingAfterNextBatch,
                                generation: generation
                            )
                        }
                    }
                case .failure:
                    self.isPreparingPDFEmbeddings = false
                    self.isEmbeddingBackfillPaused = false
                    self.embeddingBackfillNeedsRetry = true
                    self.queuedEmbeddingPriorityPageIndex = nil
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                    self.embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：失败，可重试", "AI analysis data: failed, retry available")
                    self.embeddingStatusLabel.isHidden = false
                    self.updateEmbeddingControlButtons()
                }
            }
        }
    }
}
