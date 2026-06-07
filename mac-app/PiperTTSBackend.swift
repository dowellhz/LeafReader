import Darwin
import Foundation

final class PiperTTSBackend {
    private let executableEnvironmentKey = "LEAFREADER_PIPER_CLI"
    private let voiceEnvironmentKey = "LEAFREADER_PIPER_VOICE"
    private let modelEnvironmentKey = "LEAFREADER_PIPER_MODEL"
    private let timeout: TimeInterval = 90
    let workerResponseTimeout: TimeInterval = 30
    let workerIdleShutdownDelay: TimeInterval = 45
    let maxWorkerSynthesisCount = 24

    var workerProcess: Process?
    var workerInputPipe: Pipe?
    var workerOutputPipe: Pipe?
    var workerErrorPipe: Pipe?
    var workerOutputBuffer = Data()
    var workerRuntime: PiperRuntime?
    var workerOutputDirectory: URL?
    var workerDisablesCoreML = false
    var workerSynthesisCount = 0
    var workerIdleShutdownWorkItem: DispatchWorkItem?
    var workerIdleShutdownToken = 0
    let workerStateLock = NSRecursiveLock()
    let coreMLFallbackLock = NSLock()
    var shouldDisableCoreML = false
    var coreMLFallbackDiagnostic: String?

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

    func piperEnvironment(for executableURL: URL, disableCoreML: Bool) -> [String: String] {
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

    func isCoreMLDisabled() -> Bool {
        coreMLFallbackLock.lock()
        defer { coreMLFallbackLock.unlock() }
        return shouldDisableCoreML
    }

    func recordCoreMLFallbackIfNeeded(_ diagnostic: String) {
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

    struct PiperRuntime: Equatable {
        let executableURL: URL
        let modelURL: URL
        let eSpeakDataURL: URL?
        let lengthScale: Double
    }
}
