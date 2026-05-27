import Foundation

enum SpeechRuntimeDeleter {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime
    typealias InstallManifest = SpeechRuntimeResourceManager.InstallManifest

    static func delete(_ runtime: Runtime, manifest: InstallManifest?) throws {
        SpeechRuntimeResourceManager.removePartialDownload(for: runtime)
        try SpeechRuntimePathChecks.removeItemIfExists(at: runtime.installDirectory)
        SpeechRuntimeDownloadFailureStore.clear(for: runtime)
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)

        switch runtime {
        case .kokoro:
            KokoroVoiceResourceManager.invalidateInstalledVoiceCache()
            try removeCacheDirectories(manifest?.cacheDirectories ?? SpeechRuntimePathChecks.kokoroModelCacheDirectories())
        case .piper:
            let voiceCacheDirectories = manifest?.cacheDirectories ?? SpeechRuntimePathChecks.piperVoiceCacheDirectories()
            try removeCacheDirectories(voiceCacheDirectories)
            if voiceCacheDirectories.isEmpty {
                try removeCacheDirectories(SpeechRuntimePathChecks.piperVoiceCacheDirectories())
            }
        case .kitten:
            break
        }
    }

    private static func removeCacheDirectories(_ directories: [URL]) throws {
        for directory in directories {
            try SpeechRuntimePathChecks.removeItemIfExists(at: directory)
        }
    }
}
