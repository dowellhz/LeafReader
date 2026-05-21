import Cocoa

extension AISettingsPanelController {
    private struct RuntimeStatus {
        let installed: Bool
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
            speedID: speechSpeedPopup?.selectedItem?.representedObject as? String
        )
        refreshSpeechRuntimeStatus()
    }

    @objc func speechSpeedChanged(_ sender: NSPopUpButton) {
        saveSelectedSpeechSettings(
            runtimeID: speechRuntimePopup?.selectedItem?.representedObject as? String,
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
            installed: SpeechRuntimeResourceManager.isInstalled(runtime),
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
        controls.deleteButton?.isEnabled = status.installed
        controls.downloadButton?.isHidden = status.installed || status.downloading
        controls.pauseButton?.isHidden = !status.downloading
        controls.cancelButton?.isHidden = !status.downloading
        controls.deleteButton?.isHidden = !status.installed || status.downloading
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

    func saveSelectedSpeechSettings(runtimeID: String?, speedID: String?) {
        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        let previousSpeedID = AISettingsStore.selectedSpeechSpeedID

        if let speedID {
            AISettingsStore.saveSpeechSpeedID(speedID)
        }

        guard let runtimeID,
              let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              SpeechRuntimeResourceManager.isInstalled(runtime) else {
            return
        }

        AISettingsStore.saveSelectedSpeechRuntimeID(runtimeID)

        let runtimeChanged = runtimeID != previousRuntimeID
        let speedChanged = speedID != nil && AISettingsStore.selectedSpeechSpeedID != previousSpeedID
        if runtimeChanged || speedChanged {
            KittenTTSPlayer.shared.regenerateRemainingSegmentsForUpdatedParameters()
        }
        if runtimeChanged, !KittenTTSPlayer.shared.hasActiveReadAloudWork() {
            KittenTTSPlayer.shared.shutdown()
        }
    }

    private func refreshSpeechRuntimePopup() {
        guard let popup = speechRuntimePopup else { return }
        let installedRuntimes = SpeechRuntimeResourceManager.installedReadAloudRuntimes()
        let selectedRuntime = installedRuntimes.first { $0.id == AISettingsStore.selectedSpeechRuntimeID }
            ?? installedRuntimes.first

        for item in popup.itemArray {
            guard let id = item.representedObject as? String,
                  let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: id) else { continue }
            let installed = installedRuntimes.contains(runtime)
            item.title = installed
                ? runtime.title
                : AppText.localized("\(runtime.title)（未下载）", "\(runtime.title) (Not downloaded)")
            item.isEnabled = installed
        }
        popup.isEnabled = !installedRuntimes.isEmpty
        if let selectedRuntime,
           let selectedItem = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedRuntime.id }) {
            popup.select(selectedItem)
        } else if let fallbackItem = popup.itemArray.first {
            popup.select(fallbackItem)
        }
    }

    private func downloadSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime, button: NSButton) {
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

    private func selectSpeechRuntimeAfterDownload(_ downloadedRuntime: SpeechRuntimeResourceManager.Runtime) {
        let installedRuntimes = SpeechRuntimeResourceManager.installedReadAloudRuntimes()
        guard installedRuntimes.contains(downloadedRuntime) else { return }

        let selectedRuntime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID)
        let selectedRuntimeIsInstalled = selectedRuntime.map { installedRuntimes.contains($0) } ?? false
        guard installedRuntimes.count == 1 || !selectedRuntimeIsInstalled else { return }

        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        AISettingsStore.saveSelectedSpeechRuntimeID(downloadedRuntime.id)
        guard downloadedRuntime.id != previousRuntimeID else { return }
        KittenTTSPlayer.shared.regenerateRemainingSegmentsForUpdatedParameters()
        if !KittenTTSPlayer.shared.hasActiveReadAloudWork() {
            KittenTTSPlayer.shared.shutdown()
        }
    }

    private func deleteSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        KittenTTSPlayer.shared.shutdown()
        do {
            try SpeechRuntimeResourceManager.delete(runtime)
            selectInstalledSpeechRuntimeIfNeeded(deletedRuntime: runtime)
            refreshSpeechRuntimeStatus()
        } catch {
            showSpeechDeleteError(error)
        }
    }

    private func selectInstalledSpeechRuntimeIfNeeded(deletedRuntime: SpeechRuntimeResourceManager.Runtime) {
        guard AISettingsStore.selectedSpeechRuntimeID == deletedRuntime.id else { return }
        guard let replacement = SpeechRuntimeResourceManager.installedReadAloudRuntimes().first else { return }
        AISettingsStore.saveSelectedSpeechRuntimeID(replacement.id)
    }

    private func showSpeechDownloadError(_ error: Error) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型下载失败", "Read Aloud Model Download Failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.beginSheetModal(for: panel)
    }

    private func showSpeechDeleteError(_ error: Error) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型删除失败", "Delete Read Aloud Model Failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.beginSheetModal(for: panel)
    }
}
