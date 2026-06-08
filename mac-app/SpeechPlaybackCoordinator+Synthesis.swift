import Foundation

extension SpeechPlaybackCoordinator {
    func shutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
        queue.async {
            self.forceTerminateRuntimeProcesses()
        }
        DispatchQueue.main.async {
            self.stopAndClearPlayback()
        }
    }

    func shutdownRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        let targetBackend = PreferredBackend(runtime: runtime)
        queue.async {
            guard self.activeBackend != targetBackend else {
                DispatchQueue.main.async {
                    self.shutdown()
                }
                return
            }
            switch targetBackend {
            case .kokoroCoreML:
                self.kokoroBackend.stop()
            case .piper:
                self.piperBackend.stop()
            case .supertonic:
                self.supertonicBackend.stop()
            case .none:
                break
            }
        }
    }

    func stopKokoroWorkerIfLanguageDiffers(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async {
            self.kokoroBackend.stopIfLanguageDiffers(from: trimmed)
            guard Self.preferredBackend(for: trimmed) == .kokoroCoreML else { return }
            self.kokoroBackend.prewarmIfNeeded(text: trimmed)
        }
    }

    func shutdownForTermination() {
        idleShutdownWorkItem?.cancel()
        idleShutdownWorkItem = nil
        stopAndClearPlayback()
        forceTerminateRuntimeProcesses()
    }

    func cancelScheduledIdleShutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
    }

    func scheduleIdleShutdown() {
        idleShutdownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.forceTerminateRuntimeProcesses()
            }
        }
        idleShutdownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleShutdownDelay, execute: workItem)
    }

    func generateWAV(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        generateWAVResult(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint
        ).isSuccess
    }

    func consumeLastSynthesisError() -> SpeechSynthesisError? {
        if Thread.isMainThread {
            let error = lastSynthesisError
            lastSynthesisError = nil
            return error
        }
        var error: SpeechSynthesisError?
        DispatchQueue.main.sync {
            error = self.lastSynthesisError
            self.lastSynthesisError = nil
        }
        return error
    }

    func generateWAVResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil,
        options: SynthesisOptions = .default,
        recordFailure: Bool = true
    ) -> Result<Void, SpeechSynthesisError> {
        let backend = Self.preferredBackend(for: text, languageHint: languageHint)
        prepareForBackend(backend)
        let result: Result<Void, SpeechSynthesisError>
        let runtime = backend.runtime
        switch backend {
        case .kokoroCoreML:
            result = kokoroBackend.synthesizeResult(
                text: text,
                outputURL: outputURL,
                voiceID: voiceID,
                languageHint: languageHint,
                speed: options.speedMultiplier
            )
        case .piper:
            result = piperBackend.synthesizeResult(
                text: text,
                outputURL: outputURL,
                voiceID: voiceID,
                lengthScale: options.piperLengthScale
            )
        case .supertonic:
            result = supertonicBackend.synthesizeResult(
                text: text,
                outputURL: outputURL,
                voiceID: voiceID,
                languageHint: languageHint,
                speed: options.speedMultiplier
            )
        case .none:
            result = .failure(.unsupportedLanguage(AppText.localized("当前朗读引擎", "Selected speech runtime")))
        }
        switch result {
        case .success:
            if let runtime {
                SpeechRuntimeInferenceFailureStore.clear(for: runtime)
            }
        case .failure(let error):
            if recordFailure {
                recordSynthesisFailure(
                    error,
                    text: text,
                    outputURL: outputURL,
                    voiceID: voiceID,
                    languageHint: languageHint
                )
            }
        }
        return result
    }

    func recordSynthesisFailure(
        _ error: SpeechSynthesisError,
        text: String,
        outputURL: URL,
        voiceID: String?,
        languageHint: AISettingsStore.SpeechLanguageHint?,
        context: String = "readAloud"
    ) {
        let backend = Self.preferredBackend(for: text, languageHint: languageHint)
        let runtime = backend.runtime
        let effectiveVoiceID = runtime.map {
            voiceID ?? AISettingsStore.selectedSpeechVoiceID(runtimeID: $0.id)
        }
        if let runtime {
            SpeechRuntimeInferenceFailureStore.record(
                error,
                for: runtime,
                voiceID: effectiveVoiceID,
                context: context,
                text: text,
                outputURL: outputURL
            )
        }
        logSynthesisFailure(
            error,
            runtime: runtime,
            voiceID: effectiveVoiceID,
            text: text,
            outputURL: outputURL
        )
        DispatchQueue.main.async {
            self.lastSynthesisError = error
        }
    }

    static func preferredBackend(
        for text: String,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> PreferredBackend {
        if languageHint == .chinese, SpeechRuntimeResourceManager.isRunnable(.kokoro) {
            return .kokoroCoreML
        }
        return preferredBackend(for: text)
    }

    func prepareForBackend(_ backend: PreferredBackend) {
        guard activeBackend != backend else { return }
        switch backend {
        case .kokoroCoreML:
            piperBackend.stop()
            supertonicBackend.stop()
        case .piper:
            kokoroBackend.stop()
            supertonicBackend.stop()
        case .supertonic:
            kokoroBackend.stop()
            piperBackend.stop()
        case .none:
            stopRuntimeProcesses()
        }
        activeBackend = backend
    }

    func forceTerminateRuntimeProcesses() {
        kokoroBackend.stop()
        piperBackend.stop()
        supertonicBackend.stop()
        activeBackend = nil
    }

    private func logSynthesisFailure(
        _ error: SpeechSynthesisError,
        runtime: SpeechRuntimeResourceManager.Runtime?,
        voiceID: String?,
        text: String,
        outputURL: URL
    ) {
        NSLog(
            "LeafReader TTS inference failed runtime=%@ voice=%@ textLength=%d output=%@ error=%@",
            runtime?.id ?? "none",
            voiceID ?? "none",
            text.count,
            outputURL.path,
            error.localizedDescription
        )
    }

    private func stopRuntimeProcesses() {
        kokoroBackend.stop()
        piperBackend.stop()
        supertonicBackend.stop()
        activeBackend = nil
    }
}
