import Cocoa

extension AISettingsPanelController {
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
        saveSelectedSpeechSettings(
            runtimeID: sender.selectedItem?.representedObject as? String,
            voiceID: speechVoicePopup?.selectedItem?.representedObject as? String,
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        refreshSpeechRuntimeStatus()
    }

    @objc func speechVoiceChanged(_ sender: NSPopUpButton) {
        let voiceID = sender.selectedItem?.representedObject as? String
        saveSelectedSpeechSettings(
            runtimeID: speechRuntimePopup?.selectedItem?.representedObject as? String,
            voiceID: voiceID,
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        previewSelectedKittenVoice(voiceID)
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

    func saveSelectedSpeechSettings(runtimeID: String?, voiceID: String?, speedID: String?) {
        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        let previousVoiceID = AISettingsStore.selectedKittenSpeechVoiceID
        let previousSpeedID = AISettingsStore.selectedSpeechSpeedID

        if let voiceID {
            AISettingsStore.saveKittenSpeechVoiceID(voiceID)
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
        let voiceChanged = voiceID != nil && AISettingsStore.selectedKittenSpeechVoiceID != previousVoiceID
        let speedChanged = speedID != nil && AISettingsStore.selectedSpeechSpeedID != previousSpeedID
        if runtimeChanged || voiceChanged || speedChanged {
            KittenTTSPlayer.shared.regenerateRemainingSegmentsForUpdatedParameters()
        }
        if runtimeChanged, !KittenTTSPlayer.shared.hasActiveReadAloudWork() {
            KittenTTSPlayer.shared.shutdown()
        }
    }

    private func refreshSpeechRuntimePopup() {
        guard let popup = speechRuntimePopup else { return }
        let runnableRuntimes = SpeechRuntimeResourceManager.runnableReadAloudRuntimes()
        let selectedRuntime = runnableRuntimes.first { $0.id == AISettingsStore.selectedSpeechRuntimeID }
            ?? runnableRuntimes.first

        for item in popup.itemArray {
            guard let id = item.representedObject as? String,
                  let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: id) else { continue }
            let runnable = runnableRuntimes.contains(runtime)
            if runnable {
                item.title = runtime.title
            } else if let reason = SpeechRuntimeResourceManager.availabilityText(for: runtime) {
                item.title = "\(runtime.title)（\(reason)）"
            } else {
                item.title = AppText.localized("\(runtime.title)（不可用）", "\(runtime.title) (Unavailable)")
            }
            item.isEnabled = runnable
        }
        popup.isEnabled = !runnableRuntimes.isEmpty
        if let selectedRuntime,
           let selectedItem = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedRuntime.id }) {
            popup.select(selectedItem)
        } else if let fallbackItem = popup.itemArray.first {
            popup.select(fallbackItem)
        }
    }

    private func previewSelectedKittenVoice(_ voiceID: String?) {
        guard let voiceID,
              AISettingsStore.selectedSpeechRuntimeID == SpeechRuntimeResourceManager.Runtime.kitten.id,
              SpeechRuntimeResourceManager.isRunnable(.kitten),
              !KittenTTSPlayer.shared.hasActiveReadAloudWork() else {
            return
        }
        let text = "Welcome to Leaf Reader. I'm \(voiceID), and I'll be reading this book to you."
        KittenTTSPlayer.shared.speakEnglishInterruption(text) { _ in
        } finished: {
        }
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
        KittenTTSPlayer.shared.regenerateRemainingSegmentsForUpdatedParameters()
        if !KittenTTSPlayer.shared.hasActiveReadAloudWork() {
            KittenTTSPlayer.shared.shutdown()
        }
    }

    private func deleteSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        KittenTTSPlayer.shared.shutdownRuntime(runtime)
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
