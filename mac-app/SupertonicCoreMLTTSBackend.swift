import Foundation

final class SupertonicCoreMLTTSBackend {
    private static let fallbackTimeout: TimeInterval = 90
    private static let cliEnvironmentKey = "LEAFREADER_SUPERTONIC_COREML_CLI"
    private static let modelEnvironmentKey = "LEAFREADER_SUPERTONIC_COREML_MODEL"
    private static let voiceEnvironmentKey = "LEAFREADER_SUPERTONIC_VOICE"
    private static let speedEnvironmentKey = "LEAFREADER_SUPERTONIC_SPEED"

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
            "tts",
            text,
            "--backend",
            "supertonic3",
            "--lang",
            Self.languageCode(for: text, languageHint: languageHint),
            "--voice",
            voice,
            "--total-steps",
            "8",
            "--speed",
            String(Self.speed(override: speed)),
            "--output",
            outputURL.path
        ]

        let result: ProcessRunResult
        do {
            result = try ProcessRunner.run(
                executableURL: runtime.cliURL,
                arguments: arguments,
                timeout: Self.fallbackTimeout,
                currentDirectoryURL: runtime.cliURL.deletingLastPathComponent()
            )
        } catch {
            NSLog("LeafReader Supertonic CoreML: failed to run FluidAudio CLI (error=%@)", error.localizedDescription)
            return .failure(.classifiedProcessFailure(runtime: "Supertonic", diagnostic: error.localizedDescription))
        }
        if result.timedOut {
            NSLog("LeafReader Supertonic CoreML: inference timed out after %.0fs", Self.fallbackTimeout)
            return .failure(.workerTimedOut("Supertonic"))
        }
        let outputExists = TTSWaveFile.isUsable(at: outputURL)
        if result.terminationStatus == 0, outputExists {
            return .success(())
        }
        if outputExists {
            NSLog(
                "LeafReader Supertonic CoreML: FluidAudio CLI exited with status=%d after creating audio; continuing playback (output=%@)",
                result.terminationStatus,
                outputURL.path
            )
            return .success(())
        }

        let message = Self.diagnosticTail(Self.processOutputText(stdout: result.stdout, stderr: result.stderr))
        NSLog(
            "LeafReader Supertonic CoreML: FluidAudio CLI failed (status=%d, output=%@, details=%@)",
            result.terminationStatus,
            outputURL.path,
            message
        )
        return .failure(.classifiedProcessFailure(runtime: "Supertonic", diagnostic: message))
    }

    func stop() {}

    static func runtime() -> (cliURL: URL, modelDirectoryURL: URL)? {
        guard let cliURL = cliExecutableURL() else { return nil }
        return modelDirectoryURL().map { (cliURL, $0) }
    }

    static func modelPathsExist(in directory: URL) -> Bool {
        directoryExists(directory)
            && relativeFilesExist(
                [
                    "DurationPredictor.mlmodelc",
                    "TextEncoder.mlmodelc",
                    "VectorEstimator.mlmodelc",
                    "Vocoder.mlmodelc",
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

    private static func cliExecutableURL() -> URL? {
        let userInstallRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader", isDirectory: true)
        let bundledPath = Runtime.supertonic.bundledExecutableURL.flatMap { ($0 as NSURL).path }
        let userPath = userInstallRoot
            .appendingPathComponent("supertonic-coreml", isDirectory: true)
            .appendingPathComponent("fluidaudiocli") as NSURL
        let runtimePath = Runtime.supertonic.userExecutableURL as NSURL
        let candidatePaths: [String] = [
            ProcessInfo.processInfo.environment[cliEnvironmentKey],
            bundledPath,
            userPath.path,
            runtimePath.path
        ].compactMap { $0 }
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func modelDirectoryURL() -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment[modelEnvironmentKey].map(URL.init(fileURLWithPath:)),
            Runtime.supertonicCoreMLModelCacheDirectory
        ].compactMap { $0 }
        return candidates.first(where: modelPathsExist(in:))
    }

    private static func languageCode(
        for text: String,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> String {
        switch languageHint {
        case .english:
            return "en"
        case .chinese:
            return "zh"
        case .none:
            return SpeechTextPolicy.prefersChineseTTS(text) ? "zh" : "en"
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
        let hasModel = modelPathsExist(in: Runtime.supertonicCoreMLModelCacheDirectory)
            || ProcessInfo.processInfo.environment[modelEnvironmentKey].map {
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
