import Foundation

extension SpeechRuntimeResourceManager {
    static func requiredPathsExist(_ paths: [URL]) -> Bool {
        SpeechRuntimePathChecks.requiredPathsExist(paths)
    }

    static func kittenRuntimePathsExist(in directory: URL) -> Bool {
        SpeechRuntimePathChecks.kittenRuntimePathsExist(in: directory)
    }

    static func kittenRuntimeAndModelPathsExist(installDirectories: [URL]) -> Bool {
        SpeechRuntimeAvailability.kittenRuntimeAndModelPathsExist(installDirectories: installDirectories)
    }

    static func kokoroRuntimeAndModelPathsExist(
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot
    ) -> Bool {
        SpeechRuntimeAvailability.kokoroRuntimeAndModelPathsExist(
            installDirectories: installDirectories,
            modelCacheRoot: modelCacheRoot
        )
    }

    static func piperRuntimeAndVoicePathsExist(
        installDirectories: [URL],
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory)
    ) -> Bool {
        SpeechRuntimeAvailability.piperRuntimeAndVoicePathsExist(
            installDirectories: installDirectories,
            voiceDirectory: voiceDirectory
        )
    }

    static func runtimeHealth(for runtime: Runtime) -> SpeechRuntimeHealth {
        SpeechRuntimeAvailability.health(for: runtime)
    }

    static func runtimeHealth(
        for runtime: Runtime,
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot,
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory),
        supertonicModelDirectory: URL = Runtime.supertonicCoreMLModelCacheDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SpeechRuntimeHealth {
        SpeechRuntimeAvailability.runtimeHealth(
            for: runtime,
            installDirectories: installDirectories,
            modelCacheRoot: modelCacheRoot,
            voiceDirectory: voiceDirectory,
            supertonicModelDirectory: supertonicModelDirectory,
            environment: environment
        )
    }

    static func bundledRuntimePathsExist(for runtime: Runtime) -> Bool {
        SpeechRuntimeAvailability.bundledRuntimePathsExist(for: runtime)
    }

    static func installedRuntimePathsExist(for runtime: Runtime) -> Bool {
        SpeechRuntimeAvailability.installedRuntimePathsExist(for: runtime)
    }

    static func installedRuntimePathsExist(for runtime: Runtime, installDirectories: [URL]) -> Bool {
        SpeechRuntimeAvailability.installedRuntimePathsExist(for: runtime, installDirectories: installDirectories)
    }

    static func runtimePathsExist(for runtime: Runtime, in directory: URL) -> Bool {
        SpeechRuntimeAvailability.runtimePathsExist(for: runtime, in: directory)
    }

    static func installedModelPathsExist(for runtime: Runtime) -> Bool {
        SpeechRuntimeAvailability.installedModelPathsExist(for: runtime)
    }

    static func installedModelPathsExist(
        for runtime: Runtime,
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot,
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory)
    ) -> Bool {
        SpeechRuntimeAvailability.installedModelPathsExist(
            for: runtime,
            installDirectories: installDirectories,
            modelCacheRoot: modelCacheRoot,
            voiceDirectory: voiceDirectory
        )
    }

    static func piperRuntimePathsExist(in directory: URL) -> Bool {
        SpeechRuntimePathChecks.piperRuntimePathsExist(in: directory)
    }

    static func piperVoicePathsExist(voiceID: String = SpeechVoiceCatalog.defaultPiperVoiceID) -> Bool {
        SpeechRuntimePathChecks.piperVoicePathsExist(voiceID: voiceID)
    }

    static func piperAnyVoicePathsExist() -> Bool {
        SpeechRuntimePathChecks.piperAnyVoicePathsExist()
    }

    static func piperVoicePathsExist(in modelDirectory: URL, voiceID: String = SpeechVoiceCatalog.defaultPiperVoiceID) -> Bool {
        SpeechRuntimePathChecks.piperVoicePathsExist(in: modelDirectory, voiceID: voiceID)
    }

    static func piperAnyVoicePathsExist(in modelDirectory: URL) -> Bool {
        SpeechRuntimePathChecks.piperAnyVoicePathsExist(in: modelDirectory)
    }

    static func kittenModelPathsExist(in directory: URL) -> Bool {
        SpeechRuntimePathChecks.kittenModelPathsExist(in: directory)
    }

    static func kokoroModelCacheDirectories() -> [URL] {
        SpeechRuntimePathChecks.kokoroModelCacheDirectories()
    }

    static func piperVoiceCacheDirectories() -> [URL] {
        SpeechRuntimePathChecks.piperVoiceCacheDirectories()
    }

    static func kokoroAneModelCacheExists() -> Bool {
        SpeechRuntimePathChecks.kokoroAneModelCacheExists()
    }

    static func kokoroAneModelCacheExists(in cacheRoot: URL) -> Bool {
        SpeechRuntimePathChecks.kokoroAneModelCacheExists(in: cacheRoot)
    }

    static func kokoroAneEnglishModelCacheExists(in cacheRoot: URL) -> Bool {
        SpeechRuntimePathChecks.kokoroAneEnglishModelCacheExists(in: cacheRoot)
    }

    static func kokoroAneMandarinModelCacheExists(in cacheRoot: URL) -> Bool {
        SpeechRuntimePathChecks.kokoroAneMandarinModelCacheExists(in: cacheRoot)
    }

    static func removeItemIfExists(at url: URL) throws {
        try SpeechRuntimePathChecks.removeItemIfExists(at: url)
    }
}

extension SpeechRuntimeResourceManager.InstallManifest {
    var cacheDirectories: [URL] {
        cacheDirectoryPaths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return (url.isInsideFluidAudioModelCache || url.isInsidePiperVoiceCache) ? url : nil
        }
    }
}

extension URL {
    var isInsideFluidAudioModelCache: Bool {
        isDescendant(of: SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot)
    }

    var isInsidePiperVoiceCache: Bool {
        isDescendant(of: SpeechRuntimeResourceManager.Runtime.piperVoiceCacheRoot)
    }

    private func isDescendant(of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        return standardizedFileURL.path.hasPrefix(rootPath + "/")
    }
}
