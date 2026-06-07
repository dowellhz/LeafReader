import Foundation

extension PiperTTSBackend {
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
