import Cocoa

extension AISettingsPanelController {
    private enum SpeechPreview {
        static let selectionDebounce: TimeInterval = 0.3
    }

    private struct RuntimeStatus {
        let downloaded: Bool
        let downloading: Bool
        let paused: Bool
    }

    private struct RuntimeControls {
        let statusLabel: NSTextField?
        let progressIndicator: NSProgressIndicator?
        let downloadButton: NSButton?
        let pauseButton: NSButton?
        let cancelButton: NSButton?
        let deleteButton: NSButton?
    }

    @objc func downloadKokoroSpeechRuntime(_ sender: NSButton) {
        downloadSpeechRuntime(.kokoro, button: sender)
    }

    @objc func downloadKittenSpeechRuntime(_ sender: NSButton) {
        downloadSpeechRuntime(.kitten, button: sender)
    }

    @objc func deleteKokoroSpeechRuntime(_ sender: NSButton) {
        deleteSpeechRuntime(.kokoro)
    }

    @objc func deleteKittenSpeechRuntime(_ sender: NSButton) {
        deleteSpeechRuntime(.kitten)
    }

    @objc func pauseKokoroSpeechRuntimeDownload(_ sender: NSButton) {
        toggleSpeechRuntimeDownloadPaused(.kokoro)
    }

    @objc func pauseKittenSpeechRuntimeDownload(_ sender: NSButton) {
        toggleSpeechRuntimeDownloadPaused(.kitten)
    }

    @objc func cancelKokoroSpeechRuntimeDownload(_ sender: NSButton) {
        cancelSpeechRuntimeDownload(.kokoro)
    }

    @objc func cancelKittenSpeechRuntimeDownload(_ sender: NSButton) {
        cancelSpeechRuntimeDownload(.kitten)
    }

    @objc func speechRuntimeChanged(_ sender: NSPopUpButton) {
        let runtimeID = sender.selectedItem?.representedObject as? String
        if let runtimeID,
           let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
           speechRuntimeIsBlockedByLanguage(runtime, languageHint: currentSpeechLanguageHint?()) {
            refreshSpeechRuntimePopup()
            return
        }
        saveSelectedSpeechSettings(
            runtimeID: runtimeID,
            voiceID: speechVoicePopup?.selectedItem?.representedObject as? String,
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        refreshSpeechVoicePopup(runtimeID: runtimeID)
        refreshSpeechRuntimeStatus()
    }

    @objc func speechVoiceChanged(_ sender: NSPopUpButton) {
        let voiceID = sender.selectedItem?.representedObject as? String
        let runtimeID = speechRuntimePopup?.selectedItem?.representedObject as? String
        saveSelectedSpeechSettings(
            runtimeID: runtimeID,
            voiceID: voiceID,
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        previewSelectedSpeechVoice(voiceID, runtimeID: runtimeID)
    }

    @objc func speechSpeedChanged(_ sender: NSPopUpButton) {
        saveSelectedSpeechSettings(
            runtimeID: speechRuntimePopup?.selectedItem?.representedObject as? String,
            voiceID: speechVoicePopup?.selectedItem?.representedObject as? String,
            speedID: sender.selectedItem?.representedObject as? String
        )
    }

    func refreshSpeechRuntimeStatus() {
        let kokoro = runtimeStatus(.kokoro)
        let kitten = runtimeStatus(.kitten)
        updateRuntimeControls(runtime: .kokoro, status: kokoro, controls: kokoroRuntimeControls)
        updateRuntimeControls(runtime: .kitten, status: kitten, controls: kittenRuntimeControls)
        refreshSpeechRuntimePopup()
        updateSpeechDownloadRefreshTimer(isDownloading: kokoro.downloading || kitten.downloading)
    }

    private var kokoroRuntimeControls: RuntimeControls {
        RuntimeControls(
            statusLabel: kokoroSpeechStatusLabel,
            progressIndicator: kokoroSpeechProgressIndicator,
            downloadButton: kokoroSpeechDownloadButton,
            pauseButton: kokoroSpeechPauseButton,
            cancelButton: kokoroSpeechCancelButton,
            deleteButton: kokoroSpeechDeleteButton
        )
    }

    private var kittenRuntimeControls: RuntimeControls {
        RuntimeControls(
            statusLabel: kittenSpeechStatusLabel,
            progressIndicator: kittenSpeechProgressIndicator,
            downloadButton: kittenSpeechDownloadButton,
            pauseButton: kittenSpeechPauseButton,
            cancelButton: kittenSpeechCancelButton,
            deleteButton: kittenSpeechDeleteButton
        )
    }

    private func runtimeStatus(_ runtime: SpeechRuntimeResourceManager.Runtime) -> RuntimeStatus {
        RuntimeStatus(
            downloaded: SpeechRuntimeResourceManager.isDownloaded(runtime),
            downloading: SpeechRuntimeResourceManager.isDownloading(runtime),
            paused: SpeechRuntimeResourceManager.isPaused(runtime)
        )
    }

    private func updateRuntimeControls(
        runtime: SpeechRuntimeResourceManager.Runtime,
        status: RuntimeStatus,
        controls: RuntimeControls
    ) {
        controls.statusLabel?.stringValue = SpeechRuntimeResourceManager.statusText(for: runtime)
        updateSpeechProgressIndicator(controls.progressIndicator, runtime: runtime, isDownloading: status.downloading)
        controls.pauseButton?.title = status.paused ? AppText.localized("继续", "Resume") : AppText.localized("暂停", "Pause")
        controls.downloadButton?.isEnabled = !status.downloading
        controls.deleteButton?.isEnabled = status.downloaded
        controls.downloadButton?.isHidden = status.downloaded || status.downloading
        controls.pauseButton?.isHidden = !status.downloading
        controls.cancelButton?.isHidden = !status.downloading
        controls.deleteButton?.isHidden = !status.downloaded || status.downloading
    }

    private func toggleSpeechRuntimeDownloadPaused(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        if SpeechRuntimeResourceManager.isPaused(runtime) {
            SpeechRuntimeResourceManager.resume(runtime)
        } else {
            SpeechRuntimeResourceManager.pause(runtime)
        }
        refreshSpeechRuntimeStatus()
    }

    private func cancelSpeechRuntimeDownload(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        SpeechRuntimeResourceManager.cancel(runtime)
        refreshSpeechRuntimeStatus()
    }

    private func updateSpeechProgressIndicator(
        _ indicator: NSProgressIndicator?,
        runtime: SpeechRuntimeResourceManager.Runtime,
        isDownloading: Bool
    ) {
        indicator?.isHidden = !isDownloading
        indicator?.doubleValue = SpeechRuntimeResourceManager.downloadProgress(for: runtime) ?? 0
    }

    private func updateSpeechDownloadRefreshTimer(isDownloading: Bool) {
        if isDownloading {
            guard speechDownloadRefreshTimer == nil else { return }
            speechDownloadRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refreshSpeechRuntimeStatus()
            }
        } else {
            speechDownloadRefreshTimer?.invalidate()
            speechDownloadRefreshTimer = nil
        }
    }

    func saveSelectedSpeechSettings(
        runtimeID: String?,
        voiceID: String?,
        speedID: String?
    ) {
        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        let targetRuntimeID = runtimeID ?? previousRuntimeID

        if let voiceID {
            AISettingsStore.saveSpeechVoiceID(voiceID, runtimeID: targetRuntimeID)
        }
        if let speedID {
            AISettingsStore.saveSpeechSpeedID(speedID)
        }

        guard let runtimeID,
              let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              SpeechRuntimeResourceManager.isRunnable(runtime) else {
            return
        }

        AISettingsStore.saveSelectedSpeechRuntimeID(runtimeID)

        let runtimeChanged = runtimeID != previousRuntimeID
        if runtimeChanged, !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            SpeechPlaybackCoordinator.shared.shutdown()
        }
    }

    private func refreshSpeechRuntimePopup() {
        guard let popup = speechRuntimePopup else { return }
        let languageHint = currentSpeechLanguageHint?()
        syncSpeechRuntimeForLanguageIfNeeded(languageHint: languageHint)
        let runnableRuntimes = SpeechRuntimeResourceManager.runnableReadAloudRuntimes()
        let selectedRuntime = selectedSpeechRuntimeForPopup(languageHint: languageHint, runnableRuntimes: runnableRuntimes)

        for item in popup.itemArray {
            guard let id = item.representedObject as? String,
                  let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: id) else { continue }
            let blockedByLanguage = speechRuntimeIsBlockedByLanguage(runtime, languageHint: languageHint)
            let runnable = !blockedByLanguage && runnableRuntimes.contains(runtime)
            if runnable {
                item.title = runtime.title
            } else if blockedByLanguage {
                item.title = AppText.localized("\(runtime.title)（中文使用 Kokoro）", "\(runtime.title) (Chinese uses Kokoro)")
            } else if let reason = SpeechRuntimeResourceManager.availabilityText(for: runtime) {
                item.title = "\(runtime.title)（\(reason)）"
            } else {
                item.title = AppText.localized("\(runtime.title)（不可用）", "\(runtime.title) (Unavailable)")
            }
            item.isEnabled = runnable
        }
        popup.isEnabled = selectedRuntime != nil
        if let selectedRuntime,
           let selectedItem = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedRuntime.id }) {
            popup.select(selectedItem)
        } else if let fallbackItem = popup.itemArray.first {
            popup.select(fallbackItem)
        }
        refreshSpeechVoicePopup(runtimeID: popup.selectedItem?.representedObject as? String)
    }

    private func refreshSpeechVoicePopup(runtimeID: String?) {
        guard let popup = speechVoicePopup else { return }
        let runtimeID = runtimeID ?? AISettingsStore.selectedSpeechRuntimeID
        let languageHint = currentSpeechLanguageHint?()
        let options = AISettingsStore.speechVoiceOptions(runtimeID: runtimeID, languageHint: languageHint)
        let savedVoiceID = AISettingsStore.selectedSpeechVoiceID(runtimeID: runtimeID)
        popup.removeAllItems()
        for option in options {
            popup.addItem(withTitle: option.title)
            popup.lastItem?.representedObject = option.id
        }
        if let selectedItem = popup.itemArray.first(where: { ($0.representedObject as? String) == savedVoiceID }) {
            popup.select(selectedItem)
        } else {
            popup.selectItem(at: 0)
            if let fallbackVoiceID = popup.selectedItem?.representedObject as? String {
                AISettingsStore.saveSpeechVoiceID(fallbackVoiceID, runtimeID: runtimeID)
            }
        }
    }

    private func previewSelectedSpeechVoice(_ voiceID: String?, runtimeID: String?) {
        guard let voiceID,
              let runtimeID,
              let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              SpeechRuntimeResourceManager.isRunnable(runtime),
              !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() else {
            return
        }
        let voiceTitle = AISettingsStore.speechVoiceTitle(for: voiceID, runtimeID: runtime.id)
        let languageHint = currentSpeechLanguageHint?()
        let text = runtime == .kokoro && languageHint == .chinese
            ? "欢迎使用叶子阅读，我是\(voiceTitle)，下面由我来给你阅读这本书。"
            : "Welcome to Leaf Reader. I'm \(voiceTitle), and I'll be reading this book for you. Enjoy!"
        let speedID = AISettingsStore.selectedSpeechSpeedID
        speechVoicePreviewWorkItem?.cancel()
        if runtime == .kokoro {
            SpeechPlaybackCoordinator.shared.cancelCurrentSpeechPreview(terminateKokoroWorker: true)
        }
        let workItem = DispatchWorkItem {
            SpeechPlaybackCoordinator.shared.speakCachedPreviewInterruption(
                text,
                runtimeID: runtime.id,
                voiceID: voiceID,
                speedID: speedID
            ) { _ in
            } finished: {
            }
        }
        speechVoicePreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + SpeechPreview.selectionDebounce, execute: workItem)
    }

    func effectiveSelectedSpeechRuntimeID(languageHint: AISettingsStore.SpeechLanguageHint?) -> String {
        languageHint == .chinese
            ? SpeechRuntimeResourceManager.Runtime.kokoro.id
            : AISettingsStore.selectedSpeechRuntimeID
    }

    func syncSpeechRuntimeForLanguageIfNeeded(languageHint: AISettingsStore.SpeechLanguageHint?) {
        guard languageHint == .chinese,
              SpeechRuntimeResourceManager.isRunnable(.kokoro),
              AISettingsStore.selectedSpeechRuntimeID != SpeechRuntimeResourceManager.Runtime.kokoro.id else {
            return
        }
        AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
    }

    private func selectedSpeechRuntimeForPopup(
        languageHint: AISettingsStore.SpeechLanguageHint?,
        runnableRuntimes: [SpeechRuntimeResourceManager.Runtime]
    ) -> SpeechRuntimeResourceManager.Runtime? {
        if languageHint == .chinese {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro) ? .kokoro : nil
        }
        return runnableRuntimes.first { $0.id == AISettingsStore.selectedSpeechRuntimeID }
            ?? runnableRuntimes.first
    }

    private func speechRuntimeIsBlockedByLanguage(
        _ runtime: SpeechRuntimeResourceManager.Runtime,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> Bool {
        languageHint == .chinese && runtime == .kitten
    }

    private func downloadSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime, button: NSButton) {
        if !runtime.isSupportedOnCurrentSystem {
            showUnsupportedRuntimeDownloadWarning(runtime) { [weak self, weak button] shouldContinue in
                guard let self, let button else { return }
                if shouldContinue {
                    self.startSpeechRuntimeDownload(runtime, button: button)
                } else {
                    self.refreshSpeechRuntimeStatus()
                }
            }
            return
        }

        startSpeechRuntimeDownload(runtime, button: button)
    }

    private func startSpeechRuntimeDownload(_ runtime: SpeechRuntimeResourceManager.Runtime, button: NSButton) {
        button.isEnabled = false
        SpeechRuntimeResourceManager.download(runtime) { [weak self, weak button] result in
            guard let self else { return }
            switch result {
            case .success:
                self.selectSpeechRuntimeAfterDownload(runtime)
                self.refreshSpeechRuntimeStatus()
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else {
                    self.refreshSpeechRuntimeStatus()
                    return
                }
                button?.isEnabled = true
                switch runtime {
                case .kokoro:
                    self.kokoroSpeechStatusLabel?.stringValue = AppText.localized("下载失败", "Download failed")
                case .kitten:
                    self.kittenSpeechStatusLabel?.stringValue = AppText.localized("下载失败", "Download failed")
                }
                self.showSpeechDownloadError(error)
            }
        }
        refreshSpeechRuntimeStatus()
    }

    private func showUnsupportedRuntimeDownloadWarning(
        _ runtime: SpeechRuntimeResourceManager.Runtime,
        completion: @escaping (Bool) -> Void
    ) {
        guard let panel else {
            completion(true)
            return
        }

        let alert = NSAlert()
        alert.messageText = AppText.localized("系统版本低于朗读模型要求", "System Version Below Runtime Requirement")
        alert.informativeText = AppText.localized(
            "\(runtime.title) 需要 \(runtime.minimumSystemVersionText) 或更高版本才能运行。你仍然可以下载模型，但当前系统可能无法使用它。",
            "\(runtime.title) requires \(runtime.minimumSystemVersionText) or later to run. You can still download the model, but this system may not be able to use it."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("继续下载", "Download Anyway"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: panel) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private func selectSpeechRuntimeAfterDownload(_ downloadedRuntime: SpeechRuntimeResourceManager.Runtime) {
        let runnableRuntimes = SpeechRuntimeResourceManager.runnableReadAloudRuntimes()
        guard runnableRuntimes.contains(downloadedRuntime) else { return }

        let selectedRuntime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID)
        let selectedRuntimeIsRunnable = selectedRuntime.map { runnableRuntimes.contains($0) } ?? false
        guard runnableRuntimes.count == 1 || !selectedRuntimeIsRunnable else { return }

        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        AISettingsStore.saveSelectedSpeechRuntimeID(downloadedRuntime.id)
        guard downloadedRuntime.id != previousRuntimeID else { return }
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            SpeechPlaybackCoordinator.shared.shutdown()
        }
    }

    private func deleteSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        SpeechPlaybackCoordinator.shared.shutdownRuntime(runtime)
        do {
            try SpeechRuntimeResourceManager.delete(runtime)
            selectRunnableSpeechRuntimeIfNeeded(deletedRuntime: runtime)
            refreshSpeechRuntimeStatus()
        } catch {
            showSpeechDeleteError(error)
        }
    }

    private func selectRunnableSpeechRuntimeIfNeeded(deletedRuntime: SpeechRuntimeResourceManager.Runtime) {
        guard AISettingsStore.selectedSpeechRuntimeID == deletedRuntime.id else { return }
        guard let replacement = SpeechRuntimeResourceManager.runnableReadAloudRuntimes().first else { return }
        AISettingsStore.saveSelectedSpeechRuntimeID(replacement.id)
    }

    private func showSpeechDownloadError(_ error: Error) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型下载失败", "Read Aloud Model Download Failed")
        alert.informativeText = speechRuntimeErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.beginSheetModal(for: panel)
    }

    private func showSpeechDeleteError(_ error: Error) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型删除失败", "Delete Read Aloud Model Failed")
        alert.informativeText = speechRuntimeErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.beginSheetModal(for: panel)
    }

    private func speechRuntimeErrorDescription(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AppText.localized("未知错误", "Unknown error")
        return NetworkErrorFormatter.sanitizedBody(raw.isEmpty ? fallback : raw)
    }
}
