import Foundation

enum SpeechRuntimeDownloadFailureStore {
    private static let defaultsPrefix = "speechRuntime.lastFailure."

    struct Failure: Codable {
        let message: String
        let timestamp: TimeInterval
    }

    static func failure(for runtime: SpeechRuntimeResourceManager.Runtime) -> Failure? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: runtime)) else {
            return nil
        }
        return try? JSONDecoder().decode(Failure.self, from: data)
    }

    static func record(_ error: Error, for runtime: SpeechRuntimeResourceManager.Runtime) {
        let failure = Failure(
            message: sanitizedMessage(from: error),
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

    private static func sanitizedMessage(from error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AppText.localized("未知错误", "Unknown error")
        let message = NetworkErrorFormatter.sanitizedBody(raw.isEmpty ? fallback : raw)
        if message.count > 160 {
            return "\(message.prefix(160))..."
        }
        return message
    }
}
