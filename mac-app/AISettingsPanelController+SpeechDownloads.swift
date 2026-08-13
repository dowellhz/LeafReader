import Cocoa

extension AISettingsPanelController {
    private struct RuntimeStatus {
        let downloaded: Bool
        let downloading: Bool
        let paused: Bool
    }

    private func speechRuntime(for sender: NSButton) -> SpeechRuntimeResourceManager.Runtime? {
        let runtimes = SpeechRuntimeResourceManager.Runtime.displayOrder
        guard runtimes.indices.contains(sender.tag) else { return nil }
        return runtimes[sender.tag]
    }

    @objc func downloadSpeechRuntimeButton(_ sender: NSButton) {
        guard let runtime = speechRuntime(for: sender) else { return }
        downloadSpeechRuntime(runtime, button: sender)
    }

    @objc func deleteSpeechRuntimeButton(_ sender: NSButton) {
        guard let runtime = speechRuntime(for: sender) else { return }
        deleteSpeechRuntime(runtime)
    }

    @objc func pauseSpeechRuntimeDownloadButton(_ sender: NSButton) {
        guard let runtime = speechRuntime(for: sender) else { return }
        toggleSpeechRuntimeDownloadPaused(runtime)
    }

    @objc func cancelSpeechRuntimeDownloadButton(_ sender: NSButton) {
        guard let runtime = speechRuntime(for: sender) else { return }
        SpeechRuntimeResourceManager.cancel(runtime)
        refreshSpeechRuntimeStatus()
    }

    @objc func copySpeechRuntimeDiagnosticsButton(_ sender: NSButton) {
        copySpeechRuntimeDiagnostics(error: nil, runtime: nil)
    }

    func refreshSpeechRuntimeStatus() {
        let statuses = Dictionary(
            uniqueKeysWithValues: SpeechRuntimeResourceManager.Runtime.displayOrder.map { ($0, runtimeStatus($0)) }
        )
        for runtime in SpeechRuntimeResourceManager.Runtime.displayOrder {
            guard let status = statuses[runtime],
                  let controls = speechRuntimeControls[runtime] else { continue }
            updateRuntimeControls(runtime: runtime, status: status, controls: controls)
        }
        refreshSpeechRuntimePopup()
        updateSpeechDownloadRefreshTimer(isDownloading: statuses.values.contains { $0.downloading })
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
        controls: SpeechRuntimeRowControls
    ) {
        controls.statusLabel.stringValue = SpeechRuntimeResourceManager.statusText(for: runtime)
        controls.progressIndicator.isHidden = !status.downloading
        controls.progressIndicator.doubleValue = SpeechRuntimeResourceManager.downloadProgress(for: runtime) ?? 0
        controls.pauseButton.title = status.paused ? AppText.localized("继续", "Resume") : AppText.localized("暂停", "Pause")
        controls.downloadButton.isEnabled = !status.downloading
        controls.deleteButton.isEnabled = status.downloaded
        controls.downloadButton.isHidden = status.downloaded || status.downloading
        controls.pauseButton.isHidden = !status.downloading
        controls.cancelButton.isHidden = !status.downloading
        controls.deleteButton.isHidden = !status.downloaded || status.downloading
    }

    private func toggleSpeechRuntimeDownloadPaused(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        if SpeechRuntimeResourceManager.isPaused(runtime) {
            SpeechRuntimeResourceManager.resume(runtime)
        } else {
            SpeechRuntimeResourceManager.pause(runtime)
        }
        refreshSpeechRuntimeStatus()
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
                self.speechRuntimeControls[runtime]?.statusLabel.stringValue = AppText.localized("下载失败", "Download failed")
                self.showSpeechDownloadError(error, runtime: runtime)
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
            showSpeechDeleteError(error, runtime: runtime)
        }
    }

    private func selectRunnableSpeechRuntimeIfNeeded(deletedRuntime: SpeechRuntimeResourceManager.Runtime) {
        guard AISettingsStore.selectedSpeechRuntimeID == deletedRuntime.id else { return }
        guard let replacement = SpeechRuntimeResourceManager.runnableReadAloudRuntimes().first else { return }
        AISettingsStore.saveSelectedSpeechRuntimeID(replacement.id)
    }

    private func showSpeechDownloadError(_ error: Error, runtime: SpeechRuntimeResourceManager.Runtime) {
        showSpeechRuntimeError(
            error,
            runtime: runtime,
            title: AppText.localized("朗读模型下载失败", "Read Aloud Model Download Failed")
        )
    }

    private func showSpeechDeleteError(_ error: Error, runtime: SpeechRuntimeResourceManager.Runtime) {
        showSpeechRuntimeError(
            error,
            runtime: runtime,
            title: AppText.localized("朗读模型删除失败", "Delete Read Aloud Model Failed")
        )
    }

    private func showSpeechRuntimeError(
        _ error: Error,
        runtime: SpeechRuntimeResourceManager.Runtime,
        title: String
    ) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = speechRuntimeErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.addButton(withTitle: AppText.localized("复制诊断", "Copy Diagnostics"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            self?.copySpeechRuntimeDiagnostics(error: error, runtime: runtime)
        }
    }

    private func speechRuntimeErrorDescription(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AppText.localized("未知错误", "Unknown error")
        return NetworkErrorFormatter.sanitizedBody(raw.isEmpty ? fallback : raw)
    }

    private func copySpeechRuntimeDiagnostics(error: Error?, runtime: SpeechRuntimeResourceManager.Runtime?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(speechRuntimeDiagnosticText(error: error, runtime: runtime), forType: .string)
    }

    private func speechRuntimeDiagnosticText(
        error: Error?,
        runtime selectedRuntime: SpeechRuntimeResourceManager.Runtime?
    ) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        var lines = [
            "Leaf Reader Speech Runtime Diagnostic",
            "version: \(version)",
            "selectedRuntime: \(AISettingsStore.selectedSpeechRuntimeID)",
            "selectedSpeed: \(AISettingsStore.selectedSpeechSpeedID)"
        ]
        if let error {
            lines.append("error: \(speechRuntimeErrorDescription(error))")
        }
        let runtimes = selectedRuntime.map { [$0] } ?? SpeechRuntimeResourceManager.Runtime.displayOrder
        for runtime in runtimes {
            let health = SpeechRuntimeAvailability.health(for: runtime)
            let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime)
            lines += [
                "", "[\(runtime.id)]", "title: \(runtime.title)",
                "voice: \(AISettingsStore.selectedSpeechVoiceID(runtimeID: runtime.id))",
                "supported: \(runtime.isSupportedOnCurrentSystem)",
                "minimumSystem: \(runtime.minimumSystemVersionText)",
                "downloaded: \(SpeechRuntimeResourceManager.isDownloaded(runtime))",
                "runnable: \(SpeechRuntimeResourceManager.isRunnable(runtime))",
                "downloading: \(SpeechRuntimeResourceManager.isDownloading(runtime))",
                "paused: \(SpeechRuntimeResourceManager.isPaused(runtime))",
                "installState: \(health.installState)", "hasRuntime: \(health.hasRuntime)",
                "hasModel: \(health.hasModel)", "status: \(SpeechRuntimeResourceManager.statusText(for: runtime))",
                "installDirectory: \(runtime.installDirectory.path)",
                "bundledExecutable: \(runtime.bundledExecutableURL?.path ?? "none")",
                "lastFailureContext: \(failure?.context ?? "none")",
                "lastFailureTextLength: \(failure.map { String($0.textLength) } ?? "none")",
                "lastFailureOutput: \(failure?.outputPath ?? "none")"
            ]
        }
        return lines.joined(separator: "\n")
    }
}
