import Foundation

enum SpeechRuntimeArchiveValidator {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime

    static func validate(_ runtime: Runtime, in directory: URL) throws {
        guard isValid(runtime, in: directory) else {
            throw NSError(
                domain: "LeafReader.SpeechRuntime",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "模型压缩包缺少必要文件，已保留原有模型。",
                        "The model archive is missing required files; the existing model was preserved."
                    )
                ]
            )
        }
    }

    private static func isValid(_ runtime: Runtime, in directory: URL) -> Bool {
        let hasRuntime = runtimeFilesExist(for: runtime, in: directory)
        let hasModel = packagedModelFilesExist(for: runtime, in: directory)
        return hasRuntime && hasModel
    }

    private static func runtimeFilesExist(for runtime: Runtime, in directory: URL) -> Bool {
        if SpeechRuntimeAvailability.bundledRuntimePathsExist(for: runtime) {
            return true
        }
        switch runtime {
        case .kokoro, .piper:
            return SpeechRuntimePathChecks.requiredPathsExist(runtime.requiredPaths(in: directory))
        case .supertonic:
            return SpeechRuntimePathChecks.supertonicRuntimePathsExist(in: directory)
        }
    }

    private static func packagedModelFilesExist(for runtime: Runtime, in directory: URL) -> Bool {
        switch runtime {
        case .kokoro:
            return SpeechRuntimePathChecks.kokoroAneModelCacheExists(
                in: runtime.modelDirectory(in: directory)
            )
        case .piper:
            return SpeechRuntimePathChecks.piperAnyVoicePathsExist(
                in: directory.appendingPathComponent("Voices", isDirectory: true)
            )
        case .supertonic:
            return SupertonicCoreMLTTSBackend.modelPathsExist(
                in: directory
                    .appendingPathComponent("Models", isDirectory: true)
                    .appendingPathComponent("supertonic-3", isDirectory: true)
            )
        }
    }
}
