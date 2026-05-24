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

    private func missingSpeechRuntimeInformativeText() -> String {
        if let preferredRuntime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID) {
            return missingSpeechRuntimeInformativeText(for: preferredRuntime)
        }
        return AppText.localized(
            "朗读需要先下载 Kokoro、KittenTTS 或 Piper 模型。",
            "Read aloud requires downloading a Kokoro, KittenTTS, or Piper speech model first."
        )
    }

    private func missingSpeechRuntimeInformativeText(for runtime: SpeechRuntimeResourceManager.Runtime) -> String {
        if !runtime.isSupportedOnCurrentSystem {
            return AppText.localized(
                "\(runtime.title) 需要 \(runtime.minimumSystemVersionText) 或更高版本。",
                "\(runtime.title) requires \(runtime.minimumSystemVersionText) or later."
            )
        }
        switch runtime {
        case .piper:
            let hasRuntime = runtime.installDirectories.contains {
                SpeechRuntimeResourceManager.piperRuntimePathsExist(in: $0)
            }
            let hasVoice = SpeechRuntimeResourceManager.piperAnyVoicePathsExist()
            if !hasRuntime && hasVoice {
                return AppText.localized(
                    "Piper 声音模型已下载，但 Piper runtime 不完整。请重新安装或更新应用。",
                    "The Piper voice model is downloaded, but the Piper runtime is incomplete. Reinstall or update the app."
                )
            }
            if hasRuntime && !hasVoice {
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
            let hasRuntime = runtime.installDirectories.contains {
                SpeechRuntimeResourceManager.kittenRuntimePathsExist(in: $0)
            }
            let hasModel = runtime.installDirectories.contains {
                SpeechRuntimeResourceManager.kittenModelPathsExist(in: $0)
            }
            if hasRuntime && !hasModel {
                return AppText.localized(
                    "KittenTTS runtime 已安装，但还需要下载 KittenTTS 英文模型。",
                    "The KittenTTS runtime is installed, but the English model still needs to be downloaded."
                )
            }
        case .kokoro:
            let hasRuntime = runtime.installDirectories.contains {
                FileManager.default.isExecutableFile(atPath: runtime.executableURL(in: $0).path)
            }
            let hasModel = SpeechRuntimeResourceManager.kokoroAneModelCacheExists()
            if hasRuntime && !hasModel {
                return AppText.localized(
                    "Kokoro runtime 已安装，但还需要下载 Kokoro 朗读模型。",
                    "The Kokoro runtime is installed, but the Kokoro speech model still needs to be downloaded."
                )
            }
        }
        return AppText.localized(
            "朗读需要先下载 Kokoro、KittenTTS 或 Piper 模型。",
            "Read aloud requires downloading a Kokoro, KittenTTS, or Piper speech model first."
        )
    }
}
