import Cocoa
import PDFKit

extension ReaderWindowController {
    func ensureDocumentAgentIndex() {
        guard pdfAgentIndex == nil else { return }
        if currentDocumentKind == .pdf {
            guard let document = pdfView.document else { return }
            pdfAgentIndex = PDFDocumentAgentIndex(document: document, title: titleLabel.stringValue)
            return
        }
        guard !currentWebPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pdfAgentIndex = PDFDocumentAgentIndex(text: currentWebPlainText)
    }

    func ensureDocumentAgentIndexAsync(completion: (() -> Void)? = nil) {
        if pdfAgentIndex != nil {
            completion?()
            return
        }
        if let completion {
            pendingDocumentAgentIndexCallbacks.append(completion)
        }
        guard !isBuildingDocumentAgentIndex else { return }

        isBuildingDocumentAgentIndex = true
        let generation = documentAgentIndexGeneration
        let kind = currentDocumentKind
        let title = titleLabel.stringValue

        if kind == .pdf {
            guard let url = currentFileURL else {
                finishDocumentAgentIndexBuild(nil, generation: generation)
                return
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                autoreleasepool {
                    let document = PDFDocument(url: url)
                    let index = document.map { PDFDocumentAgentIndex(document: $0, title: title) }
                    DispatchQueue.main.async {
                        self?.finishDocumentAgentIndexBuild(index, generation: generation)
                    }
                }
            }
            return
        }

        let text = currentWebPlainText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishDocumentAgentIndexBuild(nil, generation: generation)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let index = PDFDocumentAgentIndex(text: text)
            DispatchQueue.main.async {
                self?.finishDocumentAgentIndexBuild(index, generation: generation)
            }
        }
    }

    func finishDocumentAgentIndexBuild(_ index: PDFDocumentAgentIndex?, generation: Int) {
        guard generation == documentAgentIndexGeneration else { return }
        pdfAgentIndex = index
        isBuildingDocumentAgentIndex = false
        let callbacks = pendingDocumentAgentIndexCallbacks
        pendingDocumentAgentIndexCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    func currentEmbeddingPriorityIndex() -> Int? {
        if currentDocumentKind == .pdf {
            return currentPageIndex()
        }
        guard let count = pdfAgentIndex?.locationCount, count > 0 else { return nil }
        let index = Int((Double(count - 1) * min(1, max(0, webScrollProgress))).rounded())
        return min(count - 1, max(0, index))
    }

    func evidenceLocationName() -> String {
        currentDocumentKind == .pdf ? AppText.localized("Page", "Page") : AppText.localized("片段", "Section")
    }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: cacheWorkItem)

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 18.0, execute: warmupWorkItem)
    }

    var isReaderIdleForEmbedding: Bool {
        Date().timeIntervalSince(lastReaderInteractionAt) >= 4.0
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
        embeddingBackfillGeneration += 1
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        embeddingBackfillNeedsRetry = false
        queuedEmbeddingPriorityPageIndex = nil
        pendingEmbeddingReadyCallbacks.removeAll()
        cancelScheduledEmbeddingWarmup()
        clearEmbeddingStatus()
    }

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

    func currentVectorIndexStatusText() -> String {
        guard currentFileMD5 != nil else {
            return "\(AppText.noPDF)。"
        }
        let progress = pdfAgentIndex?.embeddingCoverage ?? (embedded: 0, total: 0)
        let cacheText = AppText.localized("后台统计中", "calculating")
        guard EmbeddingClient.configFromCurrentAISettings() != nil else {
            return AppText.localized("未配置向量模型。当前缓存占用 \(cacheText)。", "Embedding model is not configured. Cache uses \(cacheText).")
        }
        guard progress.total > 0 else {
            return AppText.localized("当前文档没有可索引文本。当前缓存占用 \(cacheText)。", "This document has no indexable text. Cache uses \(cacheText).")
        }
        let percent = embeddingCoveragePercent(progress)
        let state: String
        if isPreparingPDFEmbeddings {
            state = isEmbeddingBackfillPaused
                ? AppText.localized("已暂停", "paused")
                : AppText.localized("生成中", "indexing")
        } else if embeddingBackfillNeedsRetry {
            state = AppText.localized("失败，可重试", "failed, retry available")
        } else if progress.embedded >= progress.total {
            state = AppText.localized("已缓存", "cached")
        } else if scheduledEmbeddingWarmupWorkItem != nil {
            state = AppText.localized("空闲后继续", "continues when idle")
        } else if progress.embedded > 0 {
            state = AppText.localized("已缓存部分内容", "partially cached")
        } else {
            state = AppText.localized("未生成", "not built")
        }
        return AppText.localized(
            "\(state)：\(percent)%（\(progress.embedded)/\(progress.total) 个片段）。当前缓存占用 \(cacheText)。",
            "\(state): \(percent)% (\(progress.embedded)/\(progress.total) chunks). Cache uses \(cacheText)."
        )
    }

    func formatEmbeddingBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    func notifyEmbeddingReady(_ callback: (() -> Void)?, includePending: Bool) {
        callback?()
        guard includePending else { return }
        let callbacks = pendingEmbeddingReadyCallbacks
        pendingEmbeddingReadyCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    func updateEmbeddingStatus(chunks: [PDFEmbeddingChunk]) {
        let pages = Set(chunks.map(\.pageIndex)).sorted()
        guard let firstPage = pages.first else {
            clearEmbeddingStatus()
            return
        }
        let progress = pdfAgentIndex?.embeddingCoverage ?? (0, 0)
        let percent = embeddingCoveragePercent(progress)
        let text: String
        let unit = currentDocumentKind == .pdf ? AppText.localized("第", "page ") : AppText.localized("片段 ", "section ")
        let suffix = currentDocumentKind == .pdf ? AppText.localized(" 页", "") : ""
        if let lastPage = pages.last, lastPage != firstPage {
            text = AppText.localized(
                "AI 分析数据：生成中 \(percent)% \(unit)\(firstPage + 1)-\(lastPage + 1)\(suffix)",
                "AI analysis data: indexing \(percent)% \(unit)\(firstPage + 1)-\(lastPage + 1)"
            )
        } else {
            text = AppText.localized(
                "AI 分析数据：生成中 \(percent)% \(unit)\(firstPage + 1)\(suffix)",
                "AI analysis data: indexing \(percent)% \(unit)\(firstPage + 1)"
            )
        }
        embeddingStatusLabel.stringValue = text
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
    }

    func updateEmbeddingStatusForCoverage(isComplete: Bool) {
        guard let progress = pdfAgentIndex?.embeddingCoverage, progress.total > 0 else {
            clearEmbeddingStatus()
            return
        }
        let percent = embeddingCoveragePercent(progress)
        let text = isComplete || percent >= 100
            ? AppText.localized("AI 分析数据：已缓存", "AI analysis data: cached")
            : AppText.localized("AI 分析数据：已缓存 \(percent)%，空闲后继续", "AI analysis data: cached \(percent)%, continues when idle")
        embeddingStatusLabel.stringValue = text
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
    }

    func refreshEmbeddingStatusLanguage() {
        guard !embeddingStatusLabel.isHidden else { return }
        if isPreparingPDFEmbeddings {
            if isEmbeddingBackfillPaused {
                embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：已暂停，点击继续", "AI analysis data: paused, tap resume")
            } else if let progress = pdfAgentIndex?.embeddingCoverage, progress.total > 0 {
                let percent = embeddingCoveragePercent(progress)
                embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：生成中 \(percent)%", "AI analysis data: indexing \(percent)%")
            }
            updateEmbeddingControlButtons()
            return
        }
        if embeddingBackfillNeedsRetry {
            embeddingStatusLabel.stringValue = AppText.localized("AI 分析数据：失败，可重试", "AI analysis data: failed, retry available")
            updateEmbeddingControlButtons()
            return
        }
        guard let progress = pdfAgentIndex?.embeddingCoverage, progress.total > 0 else { return }
        updateEmbeddingStatusForCoverage(isComplete: progress.embedded >= progress.total)
    }

    func embeddingCoveragePercent(_ progress: (embedded: Int, total: Int)) -> Int {
        guard progress.total > 0 else { return 0 }
        return min(100, Int((Double(progress.embedded) / Double(progress.total) * 100).rounded()))
    }

    func embeddingCoveragePromptText() -> String? {
        guard let progress = pdfAgentIndex?.embeddingCoverage,
              progress.total > 0,
              progress.embedded < progress.total else {
            return nil
        }
        let percent = embeddingCoveragePercent(progress)
        return AppText.localized(
            "AI 分析数据仍在后台生成，目前覆盖 \(percent)%（\(progress.embedded)/\(progress.total) 个片段）。文档检索结果可能不完整；请先结合当前页内容、附近页面和已检索到的片段回答。",
            "AI analysis data is still being generated in the background and currently covers \(percent)% (\(progress.embedded)/\(progress.total) chunks). Document retrieval may be incomplete; answer using the current page, nearby pages, and retrieved chunks first."
        )
    }

    func clearEmbeddingStatus() {
        embeddingStatusLabel.stringValue = ""
        embeddingStatusLabel.isHidden = true
        updateEmbeddingControlButtons()
    }

    func updateEmbeddingControlButtons() {
        let showControls = isPreparingPDFEmbeddings
        embeddingPauseButton?.isHidden = !showControls
        embeddingCancelButton?.isHidden = !showControls
        embeddingPauseButton?.title = isEmbeddingBackfillPaused
            ? AppText.localized("继续", "Resume")
            : AppText.localized("暂停", "Pause")
        embeddingPauseButton?.toolTip = isEmbeddingBackfillPaused
            ? AppText.localized("继续 AI 分析", "Resume AI analysis")
            : AppText.localized("暂停 AI 分析", "Pause AI analysis")
    }

    func queryEmbedding(for question: String, completion: @escaping ([Float]?) -> Void) {
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion(nil)
            return
        }
        embeddingClient.embed(texts: [question], config: config) { result in
            if case .success(let embeddings) = result {
                completion(embeddings.first)
                return
            }
            completion(nil)
        }
    }

}
