import Darwin
import Foundation

extension PiperTTSBackend {
    func cancelWorkerIdleShutdown() {
        workerIdleShutdownWorkItem?.cancel()
        workerIdleShutdownWorkItem = nil
        workerIdleShutdownToken += 1
    }

    func scheduleWorkerIdleShutdownIfNeeded() {
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

    func stopWorkerIfIdleShutdownTokenMatches(_ token: Int) {
        workerStateLock.lock()
        defer { workerStateLock.unlock() }
        guard workerIdleShutdownToken == token else { return }
        NSLog("LeafReader PiperTTS: stopping idle worker")
        stop()
    }

    func terminateWorkerProcess(_ process: Process) {
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

    func synthesizeWithWorker(text: String, outputURL: URL, runtime: PiperRuntime) -> Bool {
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

    func ensureWorker(runtime: PiperRuntime) -> Bool {
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

    func readWorkerOutputLine(from handle: FileHandle, timeout: TimeInterval) -> String? {
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

    func nextBufferedWorkerOutputLine() -> String? {
        nextBufferedWorkerOutputLineLocked()
    }

    func nextBufferedWorkerOutputLineLocked() -> String? {
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

    static func shouldDisableCoreML(forDiagnostic diagnostic: String) -> Bool {
        let value = diagnostic.lowercased()
        return value.contains("dynamic shape is not supported")
            || value.contains("coreml does not support")
            || value.contains("failed to enable coreml execution provider")
            || value.contains("number of partitions supported by coreml: 0")
            || value.contains("number of nodes supported by coreml: 0")
    }

    static func shouldRestartWorker(synthesisCount: Int, maxSynthesisCount: Int) -> Bool {
        maxSynthesisCount > 0 && synthesisCount >= maxSynthesisCount
    }
}
