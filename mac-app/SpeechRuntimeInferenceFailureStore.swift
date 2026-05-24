import Foundation

enum SpeechRuntimeInferenceFailureStore {
    private static let defaultsPrefix = "speechRuntime.lastInferenceFailure."

    struct Failure: Codable {
        let message: String
        let runtimeID: String
        let voiceID: String?
        let context: String
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
        context: String = "readAloud",
        text: String,
        outputURL: URL
    ) {
        let failure = Failure(
            message: sanitizedMessage(from: error),
            runtimeID: runtime.id,
            voiceID: voiceID,
            context: context,
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

    static func relativeTimeText(since timestamp: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> String {
        let seconds = max(0, Int(now - timestamp))
        if seconds < 60 {
            return AppText.localized("刚刚", "just now")
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return AppText.localized("\(minutes)分钟前", "\(minutes)m ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            return AppText.localized("\(hours)小时前", "\(hours)h ago")
        }
        let days = hours / 24
        return AppText.localized("\(days)天前", "\(days)d ago")
    }

    static func contextTitle(_ context: String) -> String {
        switch context {
        case "preview":
            return AppText.localized("试听失败", "Preview failed")
        case "selection":
            return AppText.localized("选中文本朗读失败", "Selection speech failed")
        default:
            return AppText.localized("朗读失败", "Read-aloud failed")
        }
    }
}
