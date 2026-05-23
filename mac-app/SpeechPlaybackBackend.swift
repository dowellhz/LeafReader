import Foundation

extension SpeechPlaybackCoordinator {
    enum PreferredBackend {
        case kokoroCoreML
        case kitten
        case none

        init(runtime: SpeechRuntimeResourceManager.Runtime) {
            switch runtime {
            case .kokoro:
                self = .kokoroCoreML
            case .kitten:
                self = .kitten
            }
        }
    }

    static let backendEnvironmentKey = "LEAFREADER_TTS_BACKEND"

    static func preferredBackend() -> PreferredBackend {
        preferredBackend(for: "")
    }

    static func preferredBackend(for text: String) -> PreferredBackend {
        if SpeechTextPolicy.prefersChineseTTS(text) {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro) ? .kokoroCoreML : .none
        }
        let value = ProcessInfo.processInfo.environment[backendEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "kitten", "kittentts", "kitten-tts", "rust":
            return .kitten
        case "kokoro", "kokoro-coreml", "coreml":
            return .kokoroCoreML
        default:
            switch SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) {
            case .kitten:
                return .kitten
            case .kokoro:
                return .kokoroCoreML
            case .none:
                return .none
            }
        }
    }
}
