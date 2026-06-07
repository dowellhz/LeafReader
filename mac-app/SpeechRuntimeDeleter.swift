import Foundation

enum SpeechRuntimeDeleter {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime
    typealias InstallManifest = SpeechRuntimeResourceManager.InstallManifest

    static func delete(_ runtime: Runtime, manifest: InstallManifest?) throws {
        LocalRuntimeDownloadSupport.removePartialDownload(for: runtime.localRuntimeDownloadPlan)
        try SpeechRuntimePathChecks.removeItemIfExists(at: runtime.installDirectory)
        SpeechRuntimeDownloadFailureStore.clear(for: runtime)
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)

        let strategy = SpeechRuntimeCacheStrategy.strategy(for: runtime)
        if strategy.invalidatesKokoroVoiceCache {
            KokoroVoiceResourceManager.invalidateInstalledVoiceCache()
        }
        try removeCacheDirectories(strategy.deleteDirectories(from: manifest))
    }

    private static func removeCacheDirectories(_ directories: [URL]) throws {
        for directory in directories {
            try SpeechRuntimePathChecks.removeItemIfExists(at: directory)
        }
    }
}
