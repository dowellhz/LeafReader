import Foundation

final class KittenServerTTSBackend {
    private static let processServerPort = Int.random(in: 20000...49151)
    private static let modelEnvironmentKey = "LEAFREADER_KITTENTTS_RS_MODEL"
    private static let voiceEnvironmentKey = "LEAFREADER_KITTENTTS_VOICE"
    private static let speedEnvironmentKey = "LEAFREADER_KITTENTTS_SPEED"
    private static let portEnvironmentKey = "LEAFREADER_KITTENTTS_RS_PORT"

    private struct HealthCheck {
        let isHealthy: Bool
        let statusCode: Int
        let timedOut: Bool
        let hasModelResponse: Bool

        var failureDescription: String {
            if timedOut {
                return "timeout"
            }
            if statusCode != 200 {
                return "status=\(statusCode)"
            }
            return hasModelResponse ? "unknown" : "invalid model response"
        }
    }

    private var serverProcess: Process?
    private var serverOutputPipe: Pipe?
    private var serverErrorPipe: Pipe?

    func synthesize(text: String, outputURL: URL, voiceID: String? = nil) -> Bool {
        synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID).isSuccess
    }

    func synthesizeResult(text: String, outputURL: URL, voiceID: String? = nil) -> Result<Void, SpeechSynthesisError> {
        guard Self.runtime() != nil else {
            return .failure(Self.availabilityError())
        }
        if ensureServer() {
            if Self.synthesizeWithServerResult(text: text, outputURL: outputURL, voiceID: voiceID).isSuccess {
                return .success(())
            }
            stop()
            if ensureServer() {
               let retryResult = Self.synthesizeWithServerResult(text: text, outputURL: outputURL, voiceID: voiceID)
               if retryResult.isSuccess {
                return .success(())
               }
               return retryResult
            }
            return .failure(.invalidAudioOutput("KittenTTS"))
        }
        return .failure(.workerStartFailed("KittenTTS"))
    }

    func stop() {
        serverOutputPipe?.fileHandleForReading.readabilityHandler = nil
        serverErrorPipe?.fileHandleForReading.readabilityHandler = nil
        if serverProcess?.isRunning == true {
            serverProcess?.terminate()
        }
        serverProcess = nil
        serverOutputPipe = nil
        serverErrorPipe = nil
    }

    private func ensureServer() -> Bool {
        guard let runtime = Self.runtime() else { return false }
        if Self.serverHealthCheck().isHealthy {
            return true
        }
        if serverProcess?.isRunning == true {
            return waitForServer()
        }

        let arguments = [
            runtime.modelDirectoryURL.path,
            "--host",
            "127.0.0.1",
            "--port",
            String(Self.serverPort())
        ]
        var environment = ProcessInfo.processInfo.environment
        if let espeakRuntime = Self.bundledESpeakRuntime() {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(espeakRuntime.binDirectoryURL.path):\(existingPath)"
            environment["ESPEAK_DATA_PATH"] = espeakRuntime.dataDirectoryURL.path
        }
        guard let started = startDrainedProcess(
            executableURL: runtime.serverURL,
            arguments: arguments,
            environment: environment
        ) else {
            return false
        }

        serverProcess = started.process
        serverOutputPipe = started.outputPipe
        serverErrorPipe = started.errorPipe
        return waitForServer()
    }

    private func startDrainedProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) -> (process: Process, outputPipe: Pipe, errorPipe: Pipe)? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        do {
            try process.run()
            return (process, outputPipe, errorPipe)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            NSLog("LeafReader KittenTTS: failed to start process %@ (error=%@)", executableURL.path, error.localizedDescription)
            return nil
        }
    }

    private func waitForServer() -> Bool {
        var lastCheck = Self.serverHealthCheck()
        if lastCheck.isHealthy {
            return true
        }
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.2)
            lastCheck = Self.serverHealthCheck()
            if lastCheck.isHealthy {
                return true
            }
        }
        NSLog("LeafReader KittenTTS: server did not become healthy (%@, port=%d)", lastCheck.failureDescription, Self.serverPort())
        return false
    }

    private static func serverHealthCheck() -> HealthCheck {
        var request = URLRequest(url: serverURL(path: "/v1/models"))
        request.timeoutInterval = 0.5
        let result = performRequest(request)
        let hasModelResponse = isKittenServerModelsResponse(result.data)
        return HealthCheck(
            isHealthy: !result.timedOut && result.statusCode == 200 && hasModelResponse,
            statusCode: result.statusCode,
            timedOut: result.timedOut,
            hasModelResponse: hasModelResponse
        )
    }

    private static func isKittenServerModelsResponse(_ data: Data?) -> Bool {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return jsonContainsKittenTTSModel(json)
    }

    private static func jsonContainsKittenTTSModel(_ value: Any) -> Bool {
        if let string = value as? String {
            let normalized = string.lowercased()
            return normalized.contains("kitten") && normalized.contains("tts")
        }
        if let array = value as? [Any] {
            return array.contains { jsonContainsKittenTTSModel($0) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { jsonContainsKittenTTSModel($0) }
        }
        return false
    }

    private static func synthesizeWithServer(text: String, outputURL: URL, voiceID: String? = nil) -> Bool {
        synthesizeWithServerResult(text: text, outputURL: outputURL, voiceID: voiceID).isSuccess
    }

    private static func synthesizeWithServerResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil
    ) -> Result<Void, SpeechSynthesisError> {
        var request = URLRequest(url: serverURL(path: "/v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": "kitten-tts",
            "input": text,
            "voice": voiceID ?? ProcessInfo.processInfo.environment[voiceEnvironmentKey] ?? AISettingsStore.selectedKittenSpeechVoiceID,
            "speed": speed(),
            "response_format": "wav"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure(.invalidAudioOutput("KittenTTS"))
        }
        request.httpBody = body

        let result = performRequest(request)
        guard result.statusCode == 200,
              let data = result.data,
              !data.isEmpty else {
            if result.timedOut {
                NSLog("LeafReader KittenTTS: server synthesis timed out (port=%d)", serverPort())
                return .failure(.workerTimedOut("KittenTTS"))
            } else {
                NSLog(
                    "LeafReader KittenTTS: server synthesis failed (status=%d, bytes=%d, port=%d)",
                    result.statusCode,
                    result.data?.count ?? 0,
                    serverPort()
                )
                if result.statusCode == 409 || result.statusCode == 503 {
                    return .failure(.portUnavailable("KittenTTS"))
                }
                return .failure(.classifiedProcessFailure(
                    runtime: "KittenTTS",
                    diagnostic: "HTTP \(result.statusCode)"
                ))
            }
        }
        do {
            try data.write(to: outputURL, options: .atomic)
            return TTSWaveFile.isUsable(at: outputURL) ? .success(()) : .failure(.invalidAudioOutput("KittenTTS"))
        } catch {
            NSLog("LeafReader KittenTTS: failed to write server audio (error=%@)", error.localizedDescription)
            return .failure(.outputWriteFailed("KittenTTS"))
        }
    }

    private static func performRequest(_ request: URLRequest) -> (statusCode: Int, data: Data?, timedOut: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var statusCode = 0
        var responseData: Data?
        var didFinish = false
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            responseData = data
            semaphore.signal()
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + request.timeoutInterval + 1)
        if waitResult == .timedOut {
            lock.lock()
            didFinish = true
            lock.unlock()
            task.cancel()
            return (statusCode, responseData, true)
        }
        return (statusCode, responseData, false)
    }

    private static func serverURL(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(serverPort())\(path)")!
    }

    private static func serverPort() -> Int {
        if let value = ProcessInfo.processInfo.environment[portEnvironmentKey].flatMap(Int.init),
           (1...65535).contains(value) {
            return value
        }
        return processServerPort
    }

    private static func speed() -> Double {
        let value = ProcessInfo.processInfo.environment[speedEnvironmentKey]
            .flatMap(Double.init) ?? AISettingsStore.kittenSpeechSpeedMultiplier
        return min(max(value, 0.5), 2.0)
    }

    private static func bundledESpeakRuntime() -> (binDirectoryURL: URL, dataDirectoryURL: URL)? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let runtimeRoot = resourceURL
            .appendingPathComponent("SpeechRuntimes", isDirectory: true)
            .appendingPathComponent("espeak-ng", isDirectory: true)
        let binDirectoryURL = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
        let executableURL = binDirectoryURL.appendingPathComponent("espeak-ng")
        let dataDirectoryURL = runtimeRoot
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("espeak-ng-data", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.fileExists(atPath: dataDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return (binDirectoryURL, dataDirectoryURL)
    }

    private static func runtime() -> (serverURL: URL, modelDirectoryURL: URL)? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        if let modelPath = environment[modelEnvironmentKey] {
            let serverPath = SpeechRuntimeResourceManager.Runtime.kitten.userExecutableURL.path
            guard fileManager.isExecutableFile(atPath: serverPath),
                  fileManager.fileExists(atPath: modelPath) else {
                return nil
            }
            return (URL(fileURLWithPath: serverPath), URL(fileURLWithPath: modelPath))
        }

        let runtime = SpeechRuntimeResourceManager.Runtime.kitten
        let serverCandidateRoots = [runtime.bundledInstallDirectory, runtime.installDirectory].compactMap { $0 }
        let modelCandidateRoots = [runtime.installDirectory, runtime.bundledInstallDirectory].compactMap { $0 }
        for runtimeRoot in serverCandidateRoots {
            let serverURL = runtimeRoot.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
            guard fileManager.isExecutableFile(atPath: serverURL.path) else {
                continue
            }
            for modelRoot in modelCandidateRoots {
                let modelDirectoryURL = runtime.modelDirectory(in: modelRoot)
                let modelURL = modelDirectoryURL.appendingPathComponent("kitten_tts_mini_v0_8.onnx")
                let voicesURL = modelDirectoryURL.appendingPathComponent("voices.npz")
                let configURL = modelDirectoryURL.appendingPathComponent("config.json")
                guard fileManager.fileExists(atPath: modelURL.path),
                      fileManager.fileExists(atPath: voicesURL.path),
                      fileManager.fileExists(atPath: configURL.path) else {
                    continue
                }
                return (serverURL, modelDirectoryURL)
            }
        }
        return nil
    }

    private static func availabilityError() -> SpeechSynthesisError {
        let runtime = SpeechRuntimeResourceManager.Runtime.kitten
        let hasRuntime = runtime.installDirectories.contains {
            SpeechRuntimeResourceManager.kittenRuntimePathsExist(in: $0)
        }
        let hasModel = runtime.installDirectories.contains {
            SpeechRuntimeResourceManager.kittenModelPathsExist(in: $0)
        }
        if hasRuntime, !hasModel {
            return .voiceUnavailable("KittenTTS")
        }
        return .runtimeUnavailable("KittenTTS")
    }
}
