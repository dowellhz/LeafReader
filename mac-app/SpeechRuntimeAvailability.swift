import Foundation

enum SpeechRuntimeAvailability {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime
    typealias RuntimeInstallState = LocalRuntimeInstallState

    static func isDownloaded(_ runtime: Runtime) -> Bool {
        installState(for: runtime) == .complete
    }

    static func installState(for runtime: Runtime) -> RuntimeInstallState {
        installState(
            hasRuntime: installedRuntimePathsExist(for: runtime),
            hasModel: installedModelPathsExist(for: runtime)
        )
    }

    static func installState(hasRuntime: Bool, hasModel: Bool) -> RuntimeInstallState {
        LocalRuntimeInstallState.state(hasRuntime: hasRuntime, hasModel: hasModel)
    }

    static func isRunnable(_ runtime: Runtime) -> Bool {
        runtime.isSupportedOnCurrentSystem && isDownloaded(runtime)
    }

    static func runnableRuntime(preferredID: String) -> Runtime? {
        if let preferred = Runtime.runtime(for: preferredID),
           isRunnable(preferred) {
            return preferred
        }
        return runnableReadAloudRuntimes().first
    }

    static func runnableReadAloudRuntimes() -> [Runtime] {
        Runtime.displayOrder.filter(isRunnable)
    }

    static func availabilityText(for runtime: Runtime) -> String? {
        availabilityText(
            isSupported: runtime.isSupportedOnCurrentSystem,
            downloaded: isDownloaded(runtime),
            minimumSystemVersionText: runtime.minimumSystemVersionText
        )
    }

    static func availabilityText(isSupported: Bool, downloaded: Bool, minimumSystemVersionText: String) -> String? {
        LocalRuntimeStatusPresenter.availabilityText(
            isSupported: isSupported,
            downloaded: downloaded,
            minimumSystemVersionText: minimumSystemVersionText
        )
    }

    static func bundledRuntimePathsExist(for runtime: Runtime) -> Bool {
        guard let directory = runtime.bundledInstallDirectory else {
            return false
        }
        return runtimePathsExist(for: runtime, in: directory)
    }

    static func installedRuntimePathsExist(for runtime: Runtime) -> Bool {
        installedRuntimePathsExist(for: runtime, installDirectories: runtime.installDirectories)
    }

    static func installedRuntimePathsExist(for runtime: Runtime, installDirectories: [URL]) -> Bool {
        if runtime == .supertonic,
           let repoPath = ProcessInfo.processInfo.environment["LEAFREADER_SUPERTONIC_MLX_REPO"],
           SpeechRuntimePathChecks.supertonicRuntimePathsExist(in: URL(fileURLWithPath: repoPath)) {
            return true
        }
        return installDirectories.contains { directory in
            runtimePathsExist(for: runtime, in: directory)
        }
    }

    static func runtimePathsExist(for runtime: Runtime, in directory: URL) -> Bool {
        switch runtime {
        case .kitten:
            return SpeechRuntimeResourceManager.kittenRuntimePathsExist(in: directory)
        case .kokoro:
            return SpeechRuntimeResourceManager.requiredPathsExist(runtime.requiredPaths(in: directory))
        case .piper:
            return SpeechRuntimeResourceManager.piperRuntimePathsExist(in: directory)
        case .supertonic:
            return SpeechRuntimePathChecks.supertonicRuntimePathsExist(in: directory)
        }
    }

    static func installedModelPathsExist(for runtime: Runtime) -> Bool {
        installedModelPathsExist(for: runtime, installDirectories: runtime.installDirectories)
    }

    static func installedModelPathsExist(
        for runtime: Runtime,
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot,
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory)
    ) -> Bool {
        switch runtime {
        case .kitten:
            return installDirectories.contains { directory in
                SpeechRuntimeResourceManager.kittenModelPathsExist(in: directory)
            }
        case .kokoro:
            return SpeechRuntimeResourceManager.kokoroAneModelCacheExists(in: modelCacheRoot)
        case .piper:
            return SpeechRuntimeResourceManager.piperAnyVoicePathsExist(in: voiceDirectory)
        case .supertonic:
            return installDirectories.contains {
                SupertonicMLXTTSBackend.modelPathsExist(in: Runtime.supertonic.modelDirectory(in: $0))
            } || ProcessInfo.processInfo.environment["LEAFREADER_SUPERTONIC_MLX_MODEL"].map {
                SupertonicMLXTTSBackend.modelPathsExist(in: URL(fileURLWithPath: $0))
            } == true
        }
    }

    static func kittenRuntimeAndModelPathsExist(installDirectories: [URL]) -> Bool {
        installedRuntimePathsExist(for: .kitten, installDirectories: installDirectories)
            && installedModelPathsExist(for: .kitten, installDirectories: installDirectories)
    }

    static func kokoroRuntimeAndModelPathsExist(
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot
    ) -> Bool {
        installedRuntimePathsExist(for: .kokoro, installDirectories: installDirectories)
            && installedModelPathsExist(
                for: .kokoro,
                installDirectories: installDirectories,
                modelCacheRoot: modelCacheRoot
            )
    }

    static func piperRuntimeAndVoicePathsExist(
        installDirectories: [URL],
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory)
    ) -> Bool {
        installedRuntimePathsExist(for: .piper, installDirectories: installDirectories)
            && installedModelPathsExist(
                for: .piper,
                installDirectories: installDirectories,
                voiceDirectory: voiceDirectory
            )
    }
}
