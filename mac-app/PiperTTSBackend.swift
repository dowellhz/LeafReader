import Darwin
import Foundation

final class PiperTTSBackend {
    private let executableEnvironmentKey = "LEAFREADER_PIPER_CLI"
    private let voiceEnvironmentKey = "LEAFREADER_PIPER_VOICE"
    private let modelEnvironmentKey = "LEAFREADER_PIPER_MODEL"
    private let timeout: TimeInterval = 90
    private let workerResponseTimeout: TimeInterval = 30
    private let workerIdleShutdownDelay: TimeInterval = 45
    private let maxWorkerSynthesisCount = 24

    private var workerProcess: Process?
    private var workerInputPipe: Pipe?
    private var workerOutputPipe: Pipe?
    private var workerErrorPipe: Pipe?
    private var workerOutputBuffer = Data()
    private var workerRuntime: PiperRuntime?
    private var workerOutputDirectory: URL?
    private var workerDisablesCoreML = false
    private var workerSynthesisCount = 0
    private var workerIdleShutdownWorkItem: DispatchWorkItem?
    private var workerIdleShutdownToken = 0
    private let workerStateLock = NSRecursiveLock()
    private let coreMLFallbackLock = NSLock()
    private var shouldDisableCoreML = false
    private var coreMLFallbackDiagnostic: String?

    func synthesize(text: String, outputURL: URL, voiceID: String?, lengthScale: Double? = nil) -> Bool {
        synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID, lengthScale: lengthScale).isSuccess
    }

    func synthesizeResult(
        text: String,
        outputURL: URL,
        voiceID: String?,
        lengthScale: Double? = nil
    ) -> Result<Void, SpeechSynthesisError> {
        workerStateLock.lock()
        defer { workerStateLock.unlock() }
        cancelWorkerIdleShutdown()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidAudioOutput("Piper"))
        }
        guard let runtime = resolveRuntime(voiceID: voiceID, lengthScale: lengthScale) else {
            return .failure(.runtimeUnavailable("Piper"))
        }
        try? FileManager.default.removeItem(at: outputURL)

        if lengthScale != nil {
            defer { scheduleWorkerIdleShutdownIfNeeded() }
            switch runPiperOneShot(text: trimmed, outputURL: outputURL, runtime: runtime) {
            case .success:
                return TTSWaveFile.isUsable(at: outputURL) ? .success(()) : .failure(.invalidAudioOutput("Piper"))
            case .failure(let error):
                try? FileManager.default.removeItem(at: outputURL)
                return .failure(error)
            }
        }

        if synthesizeWithWorker(text: trimmed, outputURL: outputURL, runtime: runtime) {
            return .success(())
        }

        stop()
        switch runPiperOneShot(text: trimmed, outputURL: outputURL, runtime: runtime) {
        case .success:
            return TTSWaveFile.isUsable(at: outputURL) ? .success(()) : .failure(.invalidAudioOutput("Piper"))
        case .failure(let error):
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(error)
        }
    }

    func stop() {
        workerStateLock.lock()
        defer { workerStateLock.unlock() }
        cancelWorkerIdleShutdown()
        workerOutputPipe?.fileHandleForReading.readabilityHandler = nil
        workerErrorPipe?.fileHandleForReading.readabilityHandler = nil
        workerInputPipe?.fileHandleForWriting.closeFile()
        if let workerProcess, workerProcess.isRunning {
            terminateWorkerProcess(workerProcess)
        }
        workerProcess = nil
        workerInputPipe = nil
        workerOutputPipe = nil
        workerErrorPipe = nil
        workerOutputBuffer.removeAll()
        workerRuntime = nil
        workerSynthesisCount = 0
        if let workerOutputDirectory {
            try? FileManager.default.removeItem(at: workerOutputDirectory)
        }
        workerOutputDirectory = nil
    }

    private func cancelWorkerIdleShutdown() {
        workerIdleShutdownWorkItem?.cancel()
        workerIdleShutdownWorkItem = nil
        workerIdleShutdownToken += 1
    }

    private func scheduleWorkerIdleShutdownIfNeeded() {
        guard workerProcess?.isRunning == true else { return }
        cancelWorkerIdleShutdown()
        let token = workerIdleShutdownToken
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopWorkerIfIdleShutdownTokenMatches(token)
        }
        workerIdleShutdownWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + workerIdleShutdownDelay,
            execute: workItem
        )
    }

    private func stopWorkerIfIdleShutdownTokenMatches(_ token: Int) {
        workerStateLock.lock()
        defer { workerStateLock.unlock() }
        guard workerIdleShutdownToken == token else { return }
        NSLog("LeafReader PiperTTS: stopping idle worker")
        stop()
    }

    private func terminateWorkerProcess(_ process: Process) {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }
        process.terminate()
        guard finished.wait(timeout: .now() + 1) == .timedOut,
              process.isRunning else {
            return
        }
        kill(process.processIdentifier, SIGKILL)
        _ = finished.wait(timeout: .now() + 1)
    }

    private func synthesizeWithWorker(text: String, outputURL: URL, runtime: PiperRuntime) -> Bool {
        guard ensureWorker(runtime: runtime),
              let inputPipe = workerInputPipe,
              let outputPipe = workerOutputPipe else {
            return false
        }

        do {
            let line = Self.workerInputLine(for: text)
            try inputPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            NSLog("LeafReader PiperTTS: failed to write worker request (error=%@)", error.localizedDescription)
            return false
        }

        guard let generatedPath = readWorkerOutputLine(
            from: outputPipe.fileHandleForReading,
            timeout: workerResponseTimeout
        ) else {
            NSLog("LeafReader PiperTTS: worker synthesis timed out")
            return false
        }
        guard let generatedURL = Self.workerOutputURL(
            from: generatedPath,
            outputDirectory: workerOutputDirectory
        ) else {
            NSLog("LeafReader PiperTTS: worker returned unexpected output path (%@)", generatedPath)
            return false
        }

        do {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: generatedURL, to: outputURL)
        } catch {
            NSLog(
                "LeafReader PiperTTS: failed to move worker audio from %@ to %@ (error=%@)",
                generatedURL.path,
                outputURL.path,
                error.localizedDescription
            )
            return false
        }
        guard TTSWaveFile.isUsable(at: outputURL) else {
            try? FileManager.default.removeItem(at: outputURL)
            return false
        }
        workerSynthesisCount += 1
        scheduleWorkerIdleShutdownIfNeeded()
        return true
    }

    private func ensureWorker(runtime: PiperRuntime) -> Bool {
        if Self.shouldRestartWorker(
            synthesisCount: workerSynthesisCount,
            maxSynthesisCount: maxWorkerSynthesisCount
        ) {
            NSLog(
                "LeafReader PiperTTS: restarting worker after %d synthesis request(s)",
                workerSynthesisCount
            )
            stop()
        }
        if workerProcess?.isRunning == true,
           workerRuntime == runtime,
           workerDisablesCoreML == isCoreMLDisabled() {
            return true
        }
        stop()

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-PiperWorker-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("LeafReader PiperTTS: failed to create worker output directory (error=%@)", error.localizedDescription)
            return false
        }

        var arguments = [
            "--model", runtime.modelURL.path,
            "--output_dir", outputDirectory.path,
            "--length_scale", String(format: "%.2f", runtime.lengthScale),
            "--quiet"
        ]
        if let eSpeakDataURL = runtime.eSpeakDataURL {
            arguments.append(contentsOf: ["--espeak_data", eSpeakDataURL.path])
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let disablesCoreML = isCoreMLDisabled()
        process.executableURL = runtime.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = runtime.executableURL.deletingLastPathComponent()
        process.environment = piperEnvironment(for: runtime.executableURL, disableCoreML: disablesCoreML)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let diagnostic = String(data: data, encoding: .utf8),
                  !diagnostic.isEmpty else {
                return
            }
            self?.recordCoreMLFallbackIfNeeded(diagnostic)
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? FileManager.default.removeItem(at: outputDirectory)
            NSLog("LeafReader PiperTTS: failed to start worker %@: %@", runtime.executableURL.path, String(describing: error))
            return false
        }

        workerProcess = process
        workerInputPipe = inputPipe
        workerOutputPipe = outputPipe
        workerErrorPipe = errorPipe
        workerOutputBuffer.removeAll()
        workerRuntime = runtime
        workerOutputDirectory = outputDirectory
        workerDisablesCoreML = disablesCoreML
        workerSynthesisCount = 0
        return true
    }

    private func runPiperOneShot(
        text: String,
        outputURL: URL,
        runtime: PiperRuntime
    ) -> Result<Void, SpeechSynthesisError> {
        var arguments = [
            "--model", runtime.modelURL.path,
            "--output_file", outputURL.path,
            "--length_scale", String(format: "%.2f", runtime.lengthScale)
        ]
        if let eSpeakDataURL = runtime.eSpeakDataURL {
            arguments.append(contentsOf: ["--espeak_data", eSpeakDataURL.path])
        }
        return runPiper(runtime.executableURL, arguments: arguments, input: text + "\n")
    }

    private func resolveRuntime(voiceID: String?, lengthScale: Double? = nil) -> PiperRuntime? {
        let environment = ProcessInfo.processInfo.environment
        let selectedVoiceID = environment[voiceEnvironmentKey] ?? voiceID ?? AISettingsStore.selectedPiperSpeechVoiceID
        let modelFileName = "\(selectedVoiceID).onnx"
        let lengthScale = lengthScale ?? AISettingsStore.piperLengthScale

        if let executablePath = environment[executableEnvironmentKey],
           let modelPath = environment[modelEnvironmentKey] {
            let executableURL = URL(fileURLWithPath: executablePath)
            let modelURL = URL(fileURLWithPath: modelPath)
            if FileManager.default.isExecutableFile(atPath: executableURL.path),
               FileManager.default.fileExists(atPath: modelURL.path) {
                return PiperRuntime(
                    executableURL: executableURL,
                    modelURL: modelURL,
                    eSpeakDataURL: eSpeakDataURL(for: executableURL),
                    lengthScale: lengthScale
                )
            }
            NSLog(
                "LeafReader PiperTTS: environment runtime incomplete executable=%@ model=%@",
                executablePath,
                modelPath
            )
        }

        var sawExecutable = false
        var sawModel = false
        for directory in SpeechRuntimeResourceManager.Runtime.piper.installDirectories {
            let executableURL = SpeechRuntimeResourceManager.Runtime.piper.executableURL(in: directory)
            let modelURL = SpeechRuntimeResourceManager.Runtime.piper
                .modelDirectory(in: SpeechRuntimeResourceManager.Runtime.piper.installDirectory)
                .appendingPathComponent(modelFileName)
            let hasExecutable = FileManager.default.isExecutableFile(atPath: executableURL.path)
            let hasModel = FileManager.default.fileExists(atPath: modelURL.path)
            sawExecutable = sawExecutable || hasExecutable
            sawModel = sawModel || hasModel
            if hasExecutable, hasModel {
                return PiperRuntime(
                    executableURL: executableURL,
                    modelURL: modelURL,
                    eSpeakDataURL: eSpeakDataURL(for: executableURL),
                    lengthScale: lengthScale
                )
            }
        }
        NSLog(
            "LeafReader PiperTTS: runtime unavailable executable=%d model=%d voice=%@ modelDirectory=%@",
            sawExecutable,
            sawModel,
            selectedVoiceID,
            SpeechRuntimeResourceManager.Runtime.piper
                .modelDirectory(in: SpeechRuntimeResourceManager.Runtime.piper.installDirectory).path
        )
        return nil
    }

    private func readWorkerOutputLine(from handle: FileHandle, timeout: TimeInterval) -> String? {
        if let line = nextBufferedWorkerOutputLine() {
            return line
        }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var matchedLine: String?
        var didComplete = false

        handle.readabilityHandler = { [weak self] readableHandle in
            guard let self else { return }
            let data = readableHandle.availableData
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return }
            guard !data.isEmpty else {
                didComplete = true
                semaphore.signal()
                return
            }

            self.workerOutputBuffer.append(data)
            if let line = self.nextBufferedWorkerOutputLineLocked() {
                matchedLine = line
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
        return matchedLine
    }

    private func nextBufferedWorkerOutputLine() -> String? {
        nextBufferedWorkerOutputLineLocked()
    }

    private func nextBufferedWorkerOutputLineLocked() -> String? {
        guard let newlineIndex = workerOutputBuffer.firstIndex(of: 0x0A) else {
            return nil
        }
        let lineData = workerOutputBuffer.prefix(upTo: newlineIndex)
        workerOutputBuffer.removeSubrange(...newlineIndex)
        return String(data: lineData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runPiper(
        _ executableURL: URL,
        arguments: [String],
        input: String
    ) -> Result<Void, SpeechSynthesisError> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.environment = piperEnvironment(for: executableURL, disableCoreML: isCoreMLDisabled())

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
            if let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()
        } catch {
            try? stdinPipe.fileHandleForWriting.close()
            NSLog("LeafReader PiperTTS: failed to launch %@: %@", executableURL.path, String(describing: error))
            return .failure(.classifiedProcessFailure(runtime: "Piper", diagnostic: error.localizedDescription))
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut && process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recordCoreMLFallbackIfNeeded(stderr)
        let ok = !timedOut && !process.isRunning && process.terminationStatus == 0
        if !ok {
            NSLog(
                "LeafReader PiperTTS: process failed status=%d timedOut=%d stderr=%@",
                process.terminationStatus,
                timedOut,
                stderr
            )
            return .failure(.classifiedProcessFailure(runtime: "Piper", diagnostic: stderr, timedOut: timedOut))
        }
        return .success(())
    }

    private func piperEnvironment(for executableURL: URL, disableCoreML: Bool) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if disableCoreML {
            environment["PIPER_DISABLE_COREML"] = "1"
        }
        let runtimeDirectory = runtimeDirectory(for: executableURL)
        let libraryDirectory = runtimeDirectory
            .appendingPathComponent("piper-phonemize/lib", isDirectory: true)
        guard FileManager.default.fileExists(atPath: libraryDirectory.path) else {
            return environment
        }
        let existingLibraryPath = environment["DYLD_LIBRARY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        environment["DYLD_LIBRARY_PATH"] = [libraryDirectory.path, existingLibraryPath]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ":")
        return environment
    }

    private func isCoreMLDisabled() -> Bool {
        coreMLFallbackLock.lock()
        defer { coreMLFallbackLock.unlock() }
        return shouldDisableCoreML
    }

    private func recordCoreMLFallbackIfNeeded(_ diagnostic: String) {
        guard Self.shouldDisableCoreML(forDiagnostic: diagnostic) else { return }
        coreMLFallbackLock.lock()
        defer { coreMLFallbackLock.unlock() }
        guard !shouldDisableCoreML else { return }
        shouldDisableCoreML = true
        coreMLFallbackDiagnostic = diagnostic
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog(
            "LeafReader PiperTTS: disabling CoreML execution provider for this session (%@)",
            coreMLFallbackDiagnostic ?? "unsupported CoreML graph"
        )
    }

    private func eSpeakDataURL(for executableURL: URL) -> URL? {
        let dataURL = runtimeDirectory(for: executableURL)
            .appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true)
        return FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : nil
    }

    private func runtimeDirectory(for executableURL: URL) -> URL {
        executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct PiperRuntime: Equatable {
        let executableURL: URL
        let modelURL: URL
        let eSpeakDataURL: URL?
        let lengthScale: Double
    }
}
