import Foundation

struct SpeechRuntimeHealth {
    let runtime: SpeechRuntimeResourceManager.Runtime
    let hasRuntime: Bool
    let hasModel: Bool

    var installState: LocalRuntimeInstallState {
        LocalRuntimeInstallState.state(hasRuntime: hasRuntime, hasModel: hasModel)
    }

    var isComplete: Bool {
        installState == .complete
    }
}

enum SpeechRuntimeAvailability {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime
    typealias RuntimeInstallState = LocalRuntimeInstallState

    static func isDownloaded(_ runtime: Runtime) -> Bool {
        health(for: runtime).isComplete
    }

    static func installState(for runtime: Runtime) -> RuntimeInstallState {
        health(for: runtime).installState
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

    static func health(for runtime: Runtime) -> SpeechRuntimeHealth {
        runtimeHealth(for: runtime, installDirectories: runtime.installDirectories)
    }

    static func runtimeHealth(
        for runtime: Runtime,
        installDirectories: [URL],
        modelCacheRoot: URL = Runtime.fluidAudioModelCacheRoot,
        voiceDirectory: URL = Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory),
        supertonicModelDirectory: URL = Runtime.supertonicCoreMLModelCacheDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SpeechRuntimeHealth {
        SpeechRuntimeHealth(
            runtime: runtime,
            hasRuntime: runtimePathsExist(for: runtime, installDirectories: installDirectories, environment: environment),
            hasModel: modelPathsExist(
                for: runtime,
                installDirectories: installDirectories,
                modelCacheRoot: modelCacheRoot,
                voiceDirectory: voiceDirectory,
                supertonicModelDirectory: supertonicModelDirectory,
                environment: environment
            )
        )
    }

    static func runtimePathsExist(for runtime: Runtime, in directory: URL) -> Bool {
        switch runtime {
        case .kokoro:
            return SpeechRuntimePathChecks.requiredPathsExist(runtime.requiredPaths(in: directory))
        case .piper:
            return SpeechRuntimePathChecks.piperRuntimePathsExist(in: directory)
        case .supertonic:
            return SpeechRuntimePathChecks.supertonicRuntimePathsExist(in: directory)
        }
    }

    private static func runtimePathsExist(
        for runtime: Runtime,
        installDirectories: [URL],
        environment: [String: String]
    ) -> Bool {
        if runtime == .supertonic,
           let cliPath = environment["LEAFREADER_SUPERTONIC_COREML_CLI"],
           FileManager.default.isExecutableFile(atPath: cliPath) {
            return true
        }
        return installDirectories.contains { directory in
            runtimePathsExist(for: runtime, in: directory)
        }
    }

    private static func modelPathsExist(
        for runtime: Runtime,
        installDirectories: [URL],
        modelCacheRoot: URL,
        voiceDirectory: URL,
        supertonicModelDirectory: URL,
        environment: [String: String]
    ) -> Bool {
        switch runtime {
        case .kokoro:
            return SpeechRuntimePathChecks.kokoroAneModelCacheExists(in: modelCacheRoot)
        case .piper:
            return SpeechRuntimePathChecks.piperAnyVoicePathsExist(in: voiceDirectory)
        case .supertonic:
            return SupertonicCoreMLTTSBackend.modelPathsExist(in: supertonicModelDirectory)
                || environment["LEAFREADER_SUPERTONIC_COREML_MODEL"].map {
                SupertonicCoreMLTTSBackend.modelPathsExist(in: URL(fileURLWithPath: $0))
            } == true
        }
    }

}
