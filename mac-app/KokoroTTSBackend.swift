import Foundation

final class KokoroTTSBackend {
    private static let responseTimeout: TimeInterval = 45
    private static let fallbackTimeout: TimeInterval = 45
    private static let cliEnvironmentKey = "LEAFREADER_KOKORO_COREML_CLI"
    private static let voiceEnvironmentKey = "LEAFREADER_KOKORO_COREML_VOICE"
    private static let speedEnvironmentKey = "LEAFREADER_KOKORO_COREML_SPEED"

    private struct Request: Codable {
        let id: String
        let text: String
        let output: String
        let voice: String?
        let speed: Double?
    }

    private var workerProcess: Process?
    private var workerInputPipe: Pipe?
    private var workerOutputPipe: Pipe?
    private var workerErrorPipe: Pipe?
    private var workerVariant: String?
    private var workerVoiceID: String?
    private var prewarmedWorkerKey: String?

    func synthesize(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID, languageHint: languageHint).isSuccess
    }

    func synthesizeResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Result<Void, SpeechSynthesisError> {
        if synthesizeWithWorker(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint
        ) {
            return .success(())
        }
        if Self.synthesizeWithCLI(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint
        ) {
            return .success(())
        }
        return .failure(Self.availabilityError(text: text, voiceID: voiceID, languageHint: languageHint))
    }

    func stopIfLanguageDiffers(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expectedVariant = Self.variant(for: trimmed)
        guard workerProcess?.isRunning == true,
              let currentVariant = workerVariant,
              currentVariant != expectedVariant else {
            return
        }
        stop()
    }

    func prewarmIfNeeded(
        text: String,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro),
              !trimmed.isEmpty else {
            return
        }
        let variant = Self.variant(for: trimmed, languageHint: languageHint)
        let voice = voiceID ?? Self.selectedVoiceID(forVariant: variant)
        let key = Self.workerKey(variant: variant, voiceID: voice, speed: Self.speed())
        guard prewarmedWorkerKey != key else { return }
        guard ensureWorker(variant: variant, voiceID: voice),
              let inputPipe = workerInputPipe,
              let outputPipe = workerOutputPipe else {
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-KokoroPrewarm-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let request = Request(
            id: UUID().uuidString,
            text: Self.prewarmText(forVariant: variant),
            output: outputURL.path,
            voice: voice,
            speed: Self.speed()
        )
        guard let requestData = try? JSONEncoder().encode(request) else { return }
        do {
            var line = requestData
            line.append(0x0A)
            try inputPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to write prewarm request (error=%@)", error.localizedDescription)
            stop()
            return
        }
        guard let response = readWorkerResponse(
            requestID: request.id,
            from: outputPipe.fileHandleForReading,
            timeout: Self.responseTimeout
        ) else {
            NSLog("LeafReader Kokoro CoreML: worker prewarm timed out")
            stop()
            return
        }
        if response.ok {
            prewarmedWorkerKey = key
        } else if let error = response.error, !error.isEmpty {
            NSLog("LeafReader Kokoro CoreML: worker prewarm failed (%@)", error)
        }
    }

    func stop() {
        workerErrorPipe?.fileHandleForReading.readabilityHandler = nil
        workerInputPipe?.fileHandleForWriting.closeFile()
        if workerProcess?.isRunning == true {
            workerProcess?.terminate()
        }
        workerProcess = nil
        workerInputPipe = nil
        workerOutputPipe = nil
        workerErrorPipe = nil
        workerVariant = nil
        workerVoiceID = nil
        prewarmedWorkerKey = nil
    }

    private func synthesizeWithWorker(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
            stop()
            return false
        }
        let variant = Self.variant(for: text, languageHint: languageHint)
        let voice = voiceID ?? Self.selectedVoiceID(forVariant: variant)
        guard KokoroVoiceResourceManager.ensureInstalled(voiceID: voice, variant: variant),
              ensureWorker(variant: variant, voiceID: voice),
              let inputPipe = workerInputPipe,
              let outputPipe = workerOutputPipe else {
            return false
        }

        let request = Request(
            id: UUID().uuidString,
            text: text,
            output: outputURL.path,
            voice: voice,
            speed: Self.speed()
        )
        guard let requestData = try? JSONEncoder().encode(request) else {
            return false
        }

        do {
            var line = requestData
            line.append(0x0A)
            try inputPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to write worker request (error=%@)", error.localizedDescription)
            stop()
            return false
        }

        guard let response = readWorkerResponse(
            requestID: request.id,
            from: outputPipe.fileHandleForReading,
            timeout: Self.responseTimeout
        ) else {
            NSLog("LeafReader Kokoro CoreML: worker synthesis timed out")
            stop()
            return false
        }
        if response.ok, TTSWaveFile.isUsable(at: outputURL) {
            return true
        }
        if let error = response.error, !error.isEmpty {
            NSLog("LeafReader Kokoro CoreML: worker synthesis failed (%@)", error)
        }
        return false
    }

    private func ensureWorker(variant: String, voiceID: String) -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        if workerProcess?.isRunning == true,
           workerVariant == variant,
           workerVoiceID == voiceID {
            return true
        }
        stop()
        guard let cliURL = Self.runtimeURL() else { return false }
        guard KokoroVoiceResourceManager.ensureInstalled(voiceID: voiceID, variant: variant) else {
            return false
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = cliURL
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.arguments = [
            "tts-worker",
            "--variant",
            variant,
            "--voice",
            voiceID
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to start worker (error=%@)", error.localizedDescription)
            return false
        }
        workerProcess = process
        workerVariant = variant
        workerVoiceID = voiceID
        workerInputPipe = inputPipe
        workerOutputPipe = outputPipe
        workerErrorPipe = errorPipe
        return true
    }

    private static func workerKey(variant: String, voiceID: String, speed: Double) -> String {
        "\(variant)|\(voiceID)|\(String(format: "%.3f", speed))"
    }

    private static func prewarmText(forVariant variant: String) -> String {
        variant == "zh" ? "你好。" : "Hello."
    }

    private func readWorkerResponse(
        requestID: String,
        from handle: FileHandle,
        timeout: TimeInterval
    ) -> KokoroWorkerResponse? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var reader = KokoroWorkerResponseReader(requestID: requestID)
        var matchedResponse: KokoroWorkerResponse?
        var didComplete = false

        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return }
            guard !data.isEmpty else {
                didComplete = true
                semaphore.signal()
                return
            }

            if let response = reader.append(data) {
                matchedResponse = response
                didComplete = true
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        handle.readabilityHandler = nil

        lock.lock()
        defer { lock.unlock() }
        if waitResult == .timedOut {
            didComplete = true
        }
        return matchedResponse
    }

    private static func synthesizeWithCLI(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        guard let cliURL = runtimeURL() else { return false }
        let variant = variant(for: text, languageHint: languageHint)
        let voice = voiceID ?? selectedVoiceID(forVariant: variant)
        guard KokoroVoiceResourceManager.ensureInstalled(voiceID: voice, variant: variant) else {
            return false
        }

        let arguments = [
            "tts",
            text,
            "--backend",
            "kokoro-ane",
            "--variant",
            variant,
            "--voice",
            voice,
            "--speed",
            String(speed()),
            "--output",
            outputURL.path
        ]

        let result: ProcessRunResult
        do {
            result = try ProcessRunner.run(
                executableURL: cliURL,
                arguments: arguments,
                timeout: fallbackTimeout,
                currentDirectoryURL: FileManager.default.temporaryDirectory
            )
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to run FluidAudio CLI (error=%@)", error.localizedDescription)
            return false
        }
        if result.timedOut {
            NSLog("LeafReader Kokoro CoreML: FluidAudio CLI timed out after %.0fs", fallbackTimeout)
            return false
        }
        let outputExists = TTSWaveFile.isUsable(at: outputURL)
        if result.terminationStatus == 0, outputExists {
            return true
        }

        if outputExists {
            NSLog(
                "LeafReader Kokoro CoreML: FluidAudio CLI exited with status=%d after creating audio; continuing playback (output=%@)",
                result.terminationStatus,
                outputURL.path
            )
            return true
        }

        let message = diagnosticTail(processOutputText(stdout: result.stdout, stderr: result.stderr))
        NSLog(
            "LeafReader Kokoro CoreML: FluidAudio CLI failed (status=%d, outputExists=%@, output=%@, details=%@)",
            result.terminationStatus,
            outputExists ? "yes" : "no",
            outputURL.path,
            message
        )
        return false
    }

    private static func runtimeURL() -> URL? {
        let fileManager = FileManager.default
        let environmentPath = ProcessInfo.processInfo.environment[cliEnvironmentKey]
        let candidatePaths = [
            environmentPath,
            SpeechRuntimeResourceManager.Runtime.kokoro.bundledExecutableURL?.path,
            SpeechRuntimeResourceManager.Runtime.kokoro.userExecutableURL.path,
        ].compactMap { $0 }

        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func selectedVoiceID(forVariant variant: String) -> String {
        if let environmentVoice = ProcessInfo.processInfo.environment[voiceEnvironmentKey] {
            return environmentVoice
        }
        let hint: AISettingsStore.SpeechLanguageHint = variant == "zh" ? .chinese : .english
        return AISettingsStore.selectedKokoroSpeechVoiceID(languageHint: hint)
    }

    private static func speed() -> Double {
        let value = ProcessInfo.processInfo.environment[speedEnvironmentKey]
            .flatMap(Double.init) ?? AISettingsStore.kokoroSpeechSpeedMultiplier
        return min(max(value, 0.5), 2.0)
    }

    private static func variant(for text: String, languageHint: AISettingsStore.SpeechLanguageHint? = nil) -> String {
        switch languageHint {
        case .chinese:
            return "zh"
        case .english:
            return "en"
        case .none:
            break
        }
        return SpeechTextPolicy.prefersChineseTTS(text) ? "zh" : "en"
    }

    private static func processOutputText(stdout: Data, stderr: Data) -> String {
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""
        return [stdoutText, stderrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func diagnosticTail(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.count > 2400 else { return text }
        return String(text.suffix(2400))
    }

    private static func availabilityError(
        text: String,
        voiceID: String?,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> SpeechSynthesisError {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
            let runtime = SpeechRuntimeResourceManager.Runtime.kokoro
            let hasRuntime = runtime.installDirectories.contains {
                FileManager.default.isExecutableFile(atPath: runtime.executableURL(in: $0).path)
            }
            return hasRuntime ? .voiceUnavailable("Kokoro") : .runtimeUnavailable("Kokoro")
        }
        let variant = variant(for: text, languageHint: languageHint)
        let voice = voiceID ?? selectedVoiceID(forVariant: variant)
        guard KokoroVoiceResourceManager.ensureInstalled(voiceID: voice, variant: variant) else {
            return .voiceUnavailable("Kokoro")
        }
        return .processFailed("Kokoro")
    }
}
