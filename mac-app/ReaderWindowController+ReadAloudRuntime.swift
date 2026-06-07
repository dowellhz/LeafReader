import Cocoa

extension ReaderWindowController {
    func canStartReadAloudWithLocalTTS() -> Bool {
        readAloudSpeechLanguageHint = nil
        if let probeText = currentReadAloudProbeText(),
           SpeechTextPolicy.prefersChineseReadAloudDocumentTTS(probeText) {
            guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
                showMissingChineseSpeechRuntimeAlert()
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

    func showMissingSpeechRuntimeAlert() {
        showSpeechRuntimeAlert(
            messageText: AppText.localized("需要下载朗读模型", "Read Aloud Model Required"),
            informativeText: missingSpeechRuntimeInformativeText()
        )
    }

    func showSpeechPlaybackFailureAlert() {
        let runtimeTitle = SpeechRuntimeResourceManager.Runtime
            .runtime(for: AISettingsStore.selectedSpeechRuntimeID)?
            .title ?? AppText.localized("当前朗读引擎", "the selected speech runtime")
        showSpeechRuntimeAlert(
            messageText: AppText.localized("朗读运行失败", "Read Aloud Failed"),
            informativeText: AppText.localized(
                "\(runtimeTitle) 模型已安装，但运行时启动失败。请重新安装或更新应用；如果仍失败，请在朗读设置里重新下载模型。",
                "\(runtimeTitle) is installed, but its runtime failed to start. Reinstall or update the app; if it still fails, download the model again in Read Aloud settings."
            )
        )
    }

    func showSpeechPlaybackFailureAlert(error: SpeechSynthesisError) {
        guard let window else { return }
        let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID)
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读生成失败", "Read Aloud Generation Failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: error.primaryActionTitle)
        alert.addButton(withTitle: AppText.localized("复制诊断", "Copy Diagnostics"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                if error.supportsRedownload, let runtime {
                    self.redownloadSpeechRuntime(runtime)
                } else {
                    self.openSettingsPanel(tab: .speech)
                }
            case .alertSecondButtonReturn:
                self.copySpeechDiagnostics(error: error, runtime: runtime)
            default:
                break
            }
        }
    }

    func showMissingChineseSpeechRuntimeAlert() {
        showSpeechRuntimeAlert(
            messageText: AppText.localized("需要 Kokoro 中文朗读模型", "Kokoro Chinese Model Required"),
            informativeText: AppText.localized(
                "当前内容被识别为中文，中文朗读需要 Kokoro 模型。Piper 和 KittenTTS 只支持英文。",
                "This content was detected as Chinese, which requires the Kokoro model. Piper and KittenTTS support English only."
            )
        )
    }

    private func showSpeechRuntimeAlert(messageText: String, informativeText: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.localized("打开朗读设置", "Open Read Aloud Settings"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openSettingsPanel(tab: .speech)
        }
    }

    private func redownloadSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        SpeechPlaybackCoordinator.shared.shutdownRuntime(runtime)
        do {
            try SpeechRuntimeResourceManager.delete(runtime)
        } catch {
            NSLog("LeafReader TTS: failed to delete runtime before redownload runtime=%@ error=%@", runtime.id, error.localizedDescription)
        }
        SpeechRuntimeResourceManager.download(runtime) { result in
            if case .failure(let error) = result {
                NSLog("LeafReader TTS: redownload failed runtime=%@ error=%@", runtime.id, error.localizedDescription)
            }
        }
        openSettingsPanel(tab: .speech)
    }

    private func copySpeechDiagnostics(error: SpeechSynthesisError, runtime: SpeechRuntimeResourceManager.Runtime?) {
        let text = speechDiagnosticText(error: error, runtime: runtime)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func speechDiagnosticText(error: SpeechSynthesisError, runtime: SpeechRuntimeResourceManager.Runtime?) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let runtimeID = runtime?.id ?? AISettingsStore.selectedSpeechRuntimeID
        let voiceID = runtime.map { AISettingsStore.selectedSpeechVoiceID(runtimeID: $0.id) } ?? "unknown"
        let failure = runtime.flatMap { SpeechRuntimeInferenceFailureStore.failure(for: $0) }
        return [
            "Leaf Reader TTS Diagnostic",
            "version: \(version)",
            "runtime: \(runtimeID)",
            "voice: \(voiceID)",
            "errorType: \(error.diagnosticKind)",
            "message: \(error.localizedDescription)",
            "lastFailureContext: \(failure?.context ?? "none")",
            "lastFailureTextLength: \(failure.map { String($0.textLength) } ?? "none")",
            "lastFailureOutput: \(failure?.outputPath ?? "none")",
            "runtimeDownloaded: \(runtime.map { SpeechRuntimeResourceManager.isDownloaded($0) } ?? false)",
            "runtimeRunnable: \(runtime.map { SpeechRuntimeResourceManager.isRunnable($0) } ?? false)"
        ].joined(separator: "\n")
    }

    private func missingSpeechRuntimeInformativeText() -> String {
        if let preferredRuntime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID) {
            return missingSpeechRuntimeInformativeText(for: preferredRuntime)
        }
        return AppText.localized(
            "朗读需要先安装 Kokoro、KittenTTS、Piper 或 Supertonic 模型。",
            "Read aloud requires installing a Kokoro, KittenTTS, Piper, or Supertonic speech model first."
        )
    }

    private func missingSpeechRuntimeInformativeText(for runtime: SpeechRuntimeResourceManager.Runtime) -> String {
        if !runtime.isSupportedOnCurrentSystem {
            return AppText.localized(
                "\(runtime.title) 需要 \(runtime.minimumSystemVersionText) 或更高版本。",
                "\(runtime.title) requires \(runtime.minimumSystemVersionText) or later."
            )
        }
        let health = SpeechRuntimeResourceManager.runtimeHealth(for: runtime)
        switch runtime {
        case .piper:
            if !health.hasRuntime && health.hasModel {
                return AppText.localized(
                    "Piper 声音模型已下载，但 Piper runtime 不完整。请重新安装或更新应用。",
                    "The Piper voice model is downloaded, but the Piper runtime is incomplete. Reinstall or update the app."
                )
            }
            if health.hasRuntime && !health.hasModel {
                return AppText.localized(
                    "Piper runtime 已安装，但还需要下载 Piper 声音模型。",
                    "The Piper runtime is installed, but a Piper voice model still needs to be downloaded."
                )
            }
            return AppText.localized(
                "Piper 需要 runtime 和声音模型。请在朗读设置里下载 Piper。",
                "Piper requires both its runtime and a voice model. Download Piper in Read Aloud settings."
            )
        case .kitten:
            if health.hasRuntime && !health.hasModel {
                return AppText.localized(
                    "KittenTTS runtime 已安装，但还需要下载 KittenTTS 英文模型。",
                    "The KittenTTS runtime is installed, but the English model still needs to be downloaded."
                )
            }
        case .kokoro:
            if health.hasRuntime && !health.hasModel {
                return AppText.localized(
                    "Kokoro runtime 已安装，但还需要下载 Kokoro 朗读模型。",
                    "The Kokoro runtime is installed, but the Kokoro speech model still needs to be downloaded."
                )
            }
        case .supertonic:
            if health.hasRuntime && !health.hasModel {
                return AppText.localized(
                    "Supertonic runtime 已安装，但还需要下载 Supertonic 3 CoreML FP16 模型。",
                    "The Supertonic runtime is installed, but the Supertonic 3 CoreML FP16 model is still missing."
                )
            }
            return AppText.localized(
                "Supertonic 需要安装 FluidAudio runtime 和 Supertonic 3 CoreML FP16 模型。",
                "Supertonic requires the FluidAudio runtime and the Supertonic 3 CoreML FP16 model."
            )
        }
        return AppText.localized(
            "朗读需要先安装 Kokoro、KittenTTS、Piper 或 Supertonic 模型。",
            "Read aloud requires installing a Kokoro, KittenTTS, Piper, or Supertonic speech model first."
        )
    }
}
