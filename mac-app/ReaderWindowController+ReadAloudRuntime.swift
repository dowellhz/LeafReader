import Cocoa

extension ReaderWindowController {
    func canStartReadAloudWithLocalTTS() -> Bool {
        readAloudSpeechLanguageHint = nil
        if let probeText = currentReadAloudProbeText(),
           SpeechTextPolicy.prefersChineseReadAloudDocumentTTS(probeText) {
            guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
                openSpeechSettingsForMissingChineseRuntime()
                return false
            }
            AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
            readAloudSpeechLanguageHint = .chinese
            return true
        }
        guard let runtime = SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) else {
            showMissingSpeechRuntimeAlert()
            return false
        }
        AISettingsStore.saveSelectedSpeechRuntimeID(runtime.id)
        return true
    }

    func currentReadAloudProbeText() -> String? {
        if currentDocumentKind == .pdf {
            return pdfReadAloudLanguageProbeText(pageLimit: Self.readAloudLanguageProbePageLimit)
        }
        return currentWebSelectedText.isEmpty ? currentWebPlainText : currentWebSelectedText
    }

    func canReadAloudSegmentsWithAvailableRuntime(_ segments: [SpeechPlaybackCoordinator.ReadAloudSegment]) -> Bool {
        guard readAloudSpeechLanguageHint != .chinese else {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro)
        }
        let text = segments.map(\.speechText).joined(separator: " ")
        guard SpeechTextPolicy.prefersChineseTTS(text) else { return true }
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
        return true
    }

    func readAloudSegmentsWithCurrentLanguageHint(
        _ segments: [SpeechPlaybackCoordinator.ReadAloudSegment]
    ) -> [SpeechPlaybackCoordinator.ReadAloudSegment] {
        guard let hint = readAloudSpeechLanguageHint else { return segments }
        return segments.map { $0.withSpeechLanguageHint(hint) }
    }

    func openSpeechSettingsForMissingChineseRuntime() {
        openSettingsPanel(tab: .speech)
    }

    func showMissingSpeechRuntimeAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("需要下载朗读模型", "Read Aloud Model Required")
        alert.informativeText = AppText.localized(
            "朗读需要先下载 Kokoro、KittenTTS 或 Piper 模型。",
            "Read aloud requires downloading a Kokoro, KittenTTS, or Piper speech model first."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.localized("打开朗读设置", "Open Read Aloud Settings"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openSettingsPanel(tab: .speech)
        }
    }
}
