import Foundation

final class SupertonicMLXTTSBackend {
    private static let fallbackTimeout: TimeInterval = 90
    private static let pythonEnvironmentKey = "LEAFREADER_SUPERTONIC_PYTHON"
    private static let repoEnvironmentKey = "LEAFREADER_SUPERTONIC_MLX_REPO"
    private static let modelEnvironmentKey = "LEAFREADER_SUPERTONIC_MLX_MODEL"
    private static let voiceEnvironmentKey = "LEAFREADER_SUPERTONIC_VOICE"
    private static let speedEnvironmentKey = "LEAFREADER_SUPERTONIC_SPEED"
    private static let sharedMLXPythonRuntimeName = "mlx-python-runtime"
    private static let legacySupertonicPythonRuntimeName = "supertonic-mlx-venv"

    func synthesizeResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil,
        speed: Double? = nil
    ) -> Result<Void, SpeechSynthesisError> {
        guard let runtime = Self.runtime() else {
            return .failure(Self.availabilityError())
        }
        let voice = voiceID
            ?? ProcessInfo.processInfo.environment[Self.voiceEnvironmentKey]
            ?? AISettingsStore.selectedSupertonicSpeechVoiceID
        let arguments = [
            runtime.scriptURL.path,
            "--model",
            runtime.modelDirectoryURL.path,
            "--text",
            text,
            "--lang",
            Self.languageCode(for: text, languageHint: languageHint),
            "--voice",
            voice,
            "--total-step",
            "8",
            "--speed",
            String(Self.speed(override: speed)),
            "--output",
            outputURL.path
        ]

        let result: ProcessRunResult
        do {
            result = try ProcessRunner.run(
                executableURL: runtime.pythonURL,
                arguments: arguments,
                timeout: Self.fallbackTimeout,
                currentDirectoryURL: runtime.repoDirectoryURL
            )
        } catch {
            NSLog("LeafReader Supertonic MLX: failed to run Python runtime (error=%@)", error.localizedDescription)
            return .failure(.classifiedProcessFailure(runtime: "Supertonic", diagnostic: error.localizedDescription))
        }
        if result.timedOut {
            NSLog("LeafReader Supertonic MLX: inference timed out after %.0fs", Self.fallbackTimeout)
            return .failure(.workerTimedOut("Supertonic"))
        }
        let outputExists = TTSWaveFile.isUsable(at: outputURL)
        if result.terminationStatus == 0, outputExists {
            return .success(())
        }
        if outputExists {
            NSLog(
                "LeafReader Supertonic MLX: process exited with status=%d after creating audio; continuing playback (output=%@)",
                result.terminationStatus,
                outputURL.path
            )
            return .success(())
        }

        let message = Self.diagnosticTail(Self.processOutputText(stdout: result.stdout, stderr: result.stderr))
        NSLog(
            "LeafReader Supertonic MLX: inference failed (status=%d, output=%@, details=%@)",
            result.terminationStatus,
            outputURL.path,
            message
        )
        return .failure(.classifiedProcessFailure(runtime: "Supertonic", diagnostic: message))
    }

    func stop() {}

    static func runtime() -> (pythonURL: URL, repoDirectoryURL: URL, scriptURL: URL, modelDirectoryURL: URL)? {
        guard let pythonURL = pythonExecutableURL() else { return nil }
        let fileManager = FileManager.default
        let candidateRoots = [
            ProcessInfo.processInfo.environment[repoEnvironmentKey].map(URL.init(fileURLWithPath:)),
            Runtime.supertonic.bundledInstallDirectory,
            Runtime.supertonic.installDirectory as URL?
        ].compactMap { $0 }
        let modelCandidates = [
            ProcessInfo.processInfo.environment[modelEnvironmentKey].map(URL.init(fileURLWithPath:)),
            Runtime.supertonic.modelDirectory(in: Runtime.supertonic.installDirectory),
            Runtime.supertonic.bundledInstallDirectory.map { Runtime.supertonic.modelDirectory(in: $0) }
        ].compactMap { $0 }

        for root in candidateRoots {
            let scriptURL = root.appendingPathComponent("scripts/infer_mlx.py")
            let packageURL = root.appendingPathComponent("supertonic_mlx", isDirectory: true)
            guard fileManager.fileExists(atPath: scriptURL.path),
                  directoryExists(packageURL) else {
                continue
            }
            for modelURL in modelCandidates where modelPathsExist(in: modelURL) {
                return (pythonURL, root, scriptURL, modelURL)
            }
        }
        return nil
    }

    static func modelPathsExist(in directory: URL) -> Bool {
        directoryExists(directory)
            && relativeFilesExist(
                [
                    "graphs/duration_predictor.json",
                    "graphs/text_encoder.json",
                    "graphs/vector_estimator.json",
                    "graphs/vocoder.json",
                    "weights/duration_predictor.npz",
                    "weights/text_encoder.npz",
                    "weights/vector_estimator.npz",
                    "weights/vocoder.npz",
                    "tts.json",
                    "unicode_indexer.json",
                    "voice_styles/M1.json",
                    "voice_styles/F1.json"
                ],
                in: directory
            )
    }

    private static var Runtime: SpeechRuntimeResourceManager.Runtime.Type {
        SpeechRuntimeResourceManager.Runtime.self
    }

    private static func pythonExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let userInstallRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader", isDirectory: true)
        let candidatePaths = [
            ProcessInfo.processInfo.environment[pythonEnvironmentKey],
            userInstallRoot
                .appendingPathComponent(sharedMLXPythonRuntimeName, isDirectory: true)
                .appendingPathComponent("bin/python").path,
            userInstallRoot
                .appendingPathComponent(legacySupertonicPythonRuntimeName, isDirectory: true)
                .appendingPathComponent("bin/python").path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ].compactMap { $0 }
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func languageCode(
        for text: String,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> String {
        switch languageHint {
        case .english:
            return "en"
        case .chinese:
            return "na"
        case .none:
            return SpeechTextPolicy.prefersChineseTTS(text) ? "na" : "en"
        }
    }

    private static func speed(override: Double? = nil) -> Double {
        let value = override ?? ProcessInfo.processInfo.environment[speedEnvironmentKey]
            .flatMap(Double.init) ?? AISettingsStore.supertonicSpeechSpeedMultiplier
        return min(max(value, 0.7), 2.0)
    }

    private static func availabilityError() -> SpeechSynthesisError {
        let hasRuntime = Runtime.supertonic.installDirectories.contains {
            SpeechRuntimePathChecks.supertonicRuntimePathsExist(in: $0)
        }
        let hasModel = Runtime.supertonic.installDirectories.contains {
            modelPathsExist(in: Runtime.supertonic.modelDirectory(in: $0))
        } || ProcessInfo.processInfo.environment[modelEnvironmentKey].map {
            modelPathsExist(in: URL(fileURLWithPath: $0))
        } == true
        if hasRuntime, !hasModel {
            return .voiceUnavailable("Supertonic")
        }
        return .runtimeUnavailable("Supertonic")
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func relativeFilesExist(_ relativePaths: [String], in directory: URL) -> Bool {
        relativePaths.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
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
}
