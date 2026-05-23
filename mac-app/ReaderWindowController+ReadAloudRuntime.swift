import Cocoa

extension ReaderWindowController {
    func canStartReadAloudWithLocalTTS() -> Bool {
        if let probeText = currentReadAloudProbeText(),
           SpeechTextPolicy.prefersChineseTTS(probeText) {
            guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
                openSpeechSettingsForMissingKokoro()
                return false
            }
            AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
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
            return pdfView.currentPage?.string
        }
        return currentWebSelectedText.isEmpty ? currentWebPlainText : currentWebSelectedText
    }

    func canReadAloudSegmentsWithAvailableRuntime(_ segments: [KittenTTSPlayer.ReadAloudSegment]) -> Bool {
        let text = segments.map(\.speechText).joined(separator: " ")
        guard SpeechTextPolicy.prefersChineseTTS(text) else { return true }
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
        return true
    }

    func openSpeechSettingsForMissingKokoro() {
        openSettingsPanel(tab: .speech)
    }

    func showMissingSpeechRuntimeAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("需要下载朗读模型", "Read Aloud Model Required")
        alert.informativeText = AppText.localized(
            "朗读需要先下载 Kokoro 或 KittenTTS 模型。",
            "Read aloud requires downloading a Kokoro or KittenTTS speech model first."
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
