import Cocoa

extension AISettingsPanelController {
    @objc func startCurrentVectorIndex(_ sender: NSButton) {
        guard let panel, saveCurrentSettings(in: panel) else { return }
        onStartVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    @objc func toggleCurrentVectorIndex(_ sender: NSButton) {
        onToggleVectorIndexPaused?()
        refreshCurrentVectorIndexStatus()
    }

    @objc func cancelCurrentVectorIndex(_ sender: NSButton) {
        onCancelVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    @objc func clearCurrentVectorIndex(_ sender: NSButton) {
        onClearCurrentVectorIndex?()
        refreshCurrentVectorIndexStatus()
        refreshVectorCacheStatus()
    }

    @objc func clearCurrentWordRecords(_ sender: NSButton) {
        onClearCurrentWordRecords?()
    }

    func refreshCurrentVectorIndexStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.currentIndexStatusLabel?.stringValue = self?.currentVectorIndexStatus?() ?? AppText.noPDF
            self?.refreshVectorCacheStatus()
        }
    }

    func startCacheRefreshTimer() {
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.panel?.isVisible == true else { return }
            self.currentIndexStatusLabel?.stringValue = self.currentVectorIndexStatus?() ?? AppText.noPDF
            self.refreshVectorCacheStatus()
        }
    }

    func closePanel(notifySaved: Bool) {
        guard let panel, !isClosing else { return }
        isClosing = true
        shouldNotifySavedAfterClose = notifySaved
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = nil
        removeAppActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: parentWindow)
        self.panel = nil
        isClosing = false
        let shouldNotifySaved = shouldNotifySavedAfterClose
        shouldNotifySavedAfterClose = false
        if shouldNotifySaved {
            DispatchQueue.main.async { [weak self] in
                self?.onSaved?()
            }
        }
    }

    func closeWithoutSaving() {
        closePanel(notifySaved: false)
    }

    @objc func clearVectorCache(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("清除 AI 阅读记录？", "Clear AI reading records?")
        alert.informativeText = AppText.localized(
            "这会删除本机已缓存的 AI 分析数据。之后再次使用文档问答时，会按需重新分析。",
            "This deletes locally cached AI analysis data. It will be rebuilt on demand when document Q&A is used again."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("清除", "Clear"))
        alert.addButton(withTitle: AppText.cancel)
        alert.applyLeafStyle()
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.cacheStatusLabel?.stringValue = AppText.localized("正在清除缓存...", "Clearing cache...")
            self?.vectorCacheQueue.async { [weak self] in
                PDFEmbeddingStore()?.deleteAll()
                DispatchQueue.main.async {
                    self?.refreshVectorCacheStatus()
                }
            }
        }
    }

    func refreshVectorCacheStatus() {
        vectorCacheQueue.async { [weak self] in
            let text = self?.vectorCacheStatusText() ?? ""
            DispatchQueue.main.async { [weak self] in
                guard self?.panel?.isVisible == true else { return }
                self?.cacheStatusLabel?.stringValue = text
            }
        }
    }

    func vectorCacheStatusText() -> String {
        guard let store = PDFEmbeddingStore() else {
            return AppText.localized("缓存不可用", "Cache unavailable")
        }
        let size = formatBytes(store.cacheSizeBytes())
        let count = store.documentCount()
        return AppText.localized(
            "当前占用 \(size)，已缓存 \(count) 本书籍。超过 1GB 会自动删除最久未使用的书籍缓存。",
            "Using \(size), \(count) cached book(s). When it exceeds 1GB, the least recently used book cache is removed automatically."
        )
    }

    func formatBytes(_ bytes: Int64) -> String {
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
}
