import Cocoa

extension AISettingsPanelController {
    private enum SpeechPreview {
        static let selectionDebounce: TimeInterval = 0.3
    }

    func speechRuntimeButtonTag(for runtime: SpeechRuntimeResourceManager.Runtime) -> Int {
        SpeechRuntimeResourceManager.Runtime.displayOrder.firstIndex(of: runtime) ?? -1
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
        let runtimeID = speechRuntimePopup?.selectedItem?.representedObject as? String
        let voiceID = speechVoicePopup?.selectedItem?.representedObject as? String
        saveSelectedSpeechSettings(
            runtimeID: runtimeID,
            voiceID: voiceID,
            speedID: sender.selectedItem?.representedObject as? String
        )
        previewSelectedSpeechVoice(voiceID, runtimeID: runtimeID)
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

    func refreshSpeechRuntimePopup() {
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
            ) { [weak self] _ in
                self?.refreshSpeechRuntimeStatus()
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
        languageHint == .chinese && runtime == .piper
    }

}
