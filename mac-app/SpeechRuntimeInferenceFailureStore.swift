import Foundation

enum SpeechRuntimeInferenceFailureStore {
    private static let defaultsPrefix = "speechRuntime.lastInferenceFailure."

    struct Failure: Codable {
        let message: String
        let runtimeID: String
        let voiceID: String?
        let textLength: Int
        let outputPath: String
        let timestamp: TimeInterval
    }

    static func failure(for runtime: SpeechRuntimeResourceManager.Runtime) -> Failure? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: runtime)) else {
            return nil
        }
        return try? JSONDecoder().decode(Failure.self, from: data)
    }

    static func record(
        _ error: SpeechSynthesisError,
        for runtime: SpeechRuntimeResourceManager.Runtime,
        voiceID: String?,
        text: String,
        outputURL: URL
    ) {
        let failure = Failure(
            message: sanitizedMessage(from: error),
            runtimeID: runtime.id,
            voiceID: voiceID,
            textLength: text.count,
            outputPath: outputURL.path,
            timestamp: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(failure) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey(for: runtime))
    }

    static func clear(for runtime: SpeechRuntimeResourceManager.Runtime) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: runtime))
    }

    private static func defaultsKey(for runtime: SpeechRuntimeResourceManager.Runtime) -> String {
        "\(defaultsPrefix)\(runtime.id)"
    }

    private static func sanitizedMessage(from error: SpeechSynthesisError) -> String {
        let message = NetworkErrorFormatter.sanitizedBody(error.localizedDescription)
        if message.count > 160 {
            return "\(message.prefix(160))..."
        }
        return message
    }
}
