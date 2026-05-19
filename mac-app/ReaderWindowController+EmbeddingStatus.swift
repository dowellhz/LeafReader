import Cocoa

extension ReaderWindowController {
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
}
