import Foundation

extension SpeechPlaybackCoordinator {
    enum PreferredBackend {
        case kokoroCoreML
        case piper
        case supertonic
        case none

        init(runtime: SpeechRuntimeResourceManager.Runtime) {
            switch runtime {
            case .kokoro:
                self = .kokoroCoreML
            case .piper:
                self = .piper
            case .supertonic:
                self = .supertonic
            }
        }

        var runtime: SpeechRuntimeResourceManager.Runtime? {
            switch self {
            case .kokoroCoreML:
                return .kokoro
            case .piper:
                return .piper
            case .supertonic:
                return .supertonic
            case .none:
                return nil
            }
        }
    }

    static let backendEnvironmentKey = "LEAFREADER_TTS_BACKEND"

    static func preferredBackend(for text: String) -> PreferredBackend {
        if SpeechTextPolicy.prefersChineseTTS(text) {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro) ? .kokoroCoreML : .none
        }
        let value = ProcessInfo.processInfo.environment[backendEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "piper", "piper-tts":
            return .piper
        case "supertonic", "supertonic-coreml", "supertonic-mlx":
            return .supertonic
        case "kokoro", "kokoro-coreml", "coreml":
            return .kokoroCoreML
        default:
            switch SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) {
            case .piper:
                return .piper
            case .kokoro:
                return .kokoroCoreML
            case .supertonic:
                return .supertonic
            case .none:
                return .none
            }
        }
    }
}
