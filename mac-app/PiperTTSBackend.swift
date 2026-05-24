import Darwin
import Foundation

final class PiperTTSBackend {
    private let executableEnvironmentKey = "LEAFREADER_PIPER_CLI"
    private let voiceEnvironmentKey = "LEAFREADER_PIPER_VOICE"
    private let modelEnvironmentKey = "LEAFREADER_PIPER_MODEL"
    private let timeout: TimeInterval = 90
    private let workerResponseTimeout: TimeInterval = 30

    private var workerProcess: Process?
    private var workerInputPipe: Pipe?
    private var workerOutputPipe: Pipe?
    private var workerErrorPipe: Pipe?
    private var workerOutputBuffer = Data()
    private var workerRuntime: PiperRuntime?
    private var workerOutputDirectory: URL?

    func synthesize(text: String, outputURL: URL, voiceID: String?) -> Bool {
        synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID).isSuccess
    }

    func synthesizeResult(text: String, outputURL: URL, voiceID: String?) -> Result<Void, SpeechSynthesisError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidAudioOutput("Piper"))
        }
        guard let runtime = resolveRuntime(voiceID: voiceID) else {
            return .failure(.runtimeUnavailable("Piper"))
        }
        try? FileManager.default.removeItem(at: outputURL)

        if synthesizeWithWorker(text: trimmed, outputURL: outputURL, runtime: runtime) {
            return .success(())
        }

        stop()
        guard runPiperOneShot(text: trimmed, outputURL: outputURL, runtime: runtime) else {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(.processFailed("Piper"))
        }
        return TTSWaveFile.isUsable(at: outputURL) ? .success(()) : .failure(.invalidAudioOutput("Piper"))
    }

    func stop() {
        workerOutputPipe?.fileHandleForReading.readabilityHandler = nil
        workerErrorPipe?.fileHandleForReading.readabilityHandler = nil
        workerInputPipe?.fileHandleForWriting.closeFile()
        if workerProcess?.isRunning == true {
            workerProcess?.terminate()
        }
        workerProcess = nil
        workerInputPipe = nil
        workerOutputPipe = nil
        workerErrorPipe = nil
        workerOutputBuffer.removeAll()
        workerRuntime = nil
        if let workerOutputDirectory {
            try? FileManager.default.removeItem(at: workerOutputDirectory)
        }
        workerOutputDirectory = nil
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
        return true
    }

    private func ensureWorker(runtime: PiperRuntime) -> Bool {
        if workerProcess?.isRunning == true,
           workerRuntime == runtime {
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
        process.executableURL = runtime.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = runtime.executableURL.deletingLastPathComponent()
        process.environment = piperEnvironment(for: runtime.executableURL)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
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
        return true
    }

    private func runPiperOneShot(text: String, outputURL: URL, runtime: PiperRuntime) -> Bool {
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

    private func resolveRuntime(voiceID: String?) -> PiperRuntime? {
        let environment = ProcessInfo.processInfo.environment
        let selectedVoiceID = environment[voiceEnvironmentKey] ?? voiceID ?? AISettingsStore.selectedPiperSpeechVoiceID
        let modelFileName = "\(selectedVoiceID).onnx"
        let lengthScale = AISettingsStore.piperLengthScale

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

    static func workerInputLine(for text: String) -> Data {
        let line = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data((line + "\n").utf8)
    }

    static func workerOutputURL(from line: String, outputDirectory: URL?) -> URL? {
        let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              path.hasSuffix(".wav"),
              let outputDirectory else {
            return nil
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let directoryPath = outputDirectory.standardizedFileURL.path
        guard url.deletingLastPathComponent().path == directoryPath else {
            return nil
        }
        return url
    }

    private func runPiper(_ executableURL: URL, arguments: [String], input: String) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.environment = piperEnvironment(for: executableURL)

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
            return false
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut && process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let ok = !timedOut && !process.isRunning && process.terminationStatus == 0
        if !ok {
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NSLog(
                "LeafReader PiperTTS: process failed status=%d timedOut=%d stderr=%@",
                process.terminationStatus,
                timedOut,
                stderr
            )
        }
        return ok
    }

    private func piperEnvironment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
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
