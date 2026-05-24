import Darwin
import Foundation

final class PiperTTSBackend {
    private let executableEnvironmentKey = "LEAFREADER_PIPER_CLI"
    private let voiceEnvironmentKey = "LEAFREADER_PIPER_VOICE"
    private let modelEnvironmentKey = "LEAFREADER_PIPER_MODEL"
    private let timeout: TimeInterval = 90

    func synthesize(text: String, outputURL: URL, voiceID: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let runtime = resolveRuntime(voiceID: voiceID) else {
            return false
        }
        try? FileManager.default.removeItem(at: outputURL)
        var arguments = [
            "--model", runtime.modelURL.path,
            "--output_file", outputURL.path,
            "--length_scale", String(format: "%.2f", AISettingsStore.piperLengthScale)
        ]
        if let eSpeakDataURL = eSpeakDataURL(for: runtime.executableURL) {
            arguments.append(contentsOf: ["--espeak_data", eSpeakDataURL.path])
        }
        guard runPiper(runtime.executableURL, arguments: arguments, input: trimmed + "\n") else {
            try? FileManager.default.removeItem(at: outputURL)
            return false
        }
        return TTSWaveFile.isUsable(at: outputURL)
    }

    func stop() {}

    private func resolveRuntime(voiceID: String?) -> PiperRuntime? {
        let environment = ProcessInfo.processInfo.environment
        let selectedVoiceID = environment[voiceEnvironmentKey] ?? voiceID ?? AISettingsStore.selectedPiperSpeechVoiceID
        let modelFileName = "\(selectedVoiceID).onnx"

        if let executablePath = environment[executableEnvironmentKey],
           let modelPath = environment[modelEnvironmentKey] {
            let executableURL = URL(fileURLWithPath: executablePath)
            let modelURL = URL(fileURLWithPath: modelPath)
            if FileManager.default.isExecutableFile(atPath: executableURL.path),
               FileManager.default.fileExists(atPath: modelURL.path) {
                return PiperRuntime(executableURL: executableURL, modelURL: modelURL)
            }
        }

        for directory in SpeechRuntimeResourceManager.Runtime.piper.installDirectories {
            let executableURL = SpeechRuntimeResourceManager.Runtime.piper.executableURL(in: directory)
            let modelURL = SpeechRuntimeResourceManager.Runtime.piper
                .modelDirectory(in: SpeechRuntimeResourceManager.Runtime.piper.installDirectory)
                .appendingPathComponent(modelFileName)
            if FileManager.default.isExecutableFile(atPath: executableURL.path),
               FileManager.default.fileExists(atPath: modelURL.path) {
                return PiperRuntime(executableURL: executableURL, modelURL: modelURL)
            }
        }
        return nil
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
            return false
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut && process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return !timedOut && !process.isRunning && process.terminationStatus == 0
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

    private struct PiperRuntime {
        let executableURL: URL
        let modelURL: URL
    }
}
