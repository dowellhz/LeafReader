import Foundation

extension SpeechRuntimeResourceManager {
    typealias RuntimeInstallState = LocalRuntimeInstallState

    static func isDownloaded(_ runtime: Runtime) -> Bool {
        SpeechRuntimeAvailability.isDownloaded(runtime)
    }

    static func runtimeInstallState(for runtime: Runtime) -> RuntimeInstallState {
        SpeechRuntimeAvailability.installState(for: runtime)
    }

    static func runtimeInstallState(hasRuntime: Bool, hasModel: Bool) -> RuntimeInstallState {
        SpeechRuntimeAvailability.installState(hasRuntime: hasRuntime, hasModel: hasModel)
    }

    static func isRunnable(_ runtime: Runtime) -> Bool {
        SpeechRuntimeAvailability.isRunnable(runtime)
    }

    static func availabilityText(for runtime: Runtime) -> String? {
        SpeechRuntimeAvailability.availabilityText(for: runtime)
    }

    static func availabilityText(isSupported: Bool, downloaded: Bool, minimumSystemVersionText: String) -> String? {
        SpeechRuntimeAvailability.availabilityText(
            isSupported: isSupported,
            downloaded: downloaded,
            minimumSystemVersionText: minimumSystemVersionText
        )
    }

    static func runnableRuntime(preferredID: String) -> Runtime? {
        SpeechRuntimeAvailability.runnableRuntime(preferredID: preferredID)
    }

    static func runnableReadAloudRuntimes() -> [Runtime] {
        SpeechRuntimeAvailability.runnableReadAloudRuntimes()
    }

    static func statusText(for runtime: Runtime) -> String {
        LocalRuntimeStatusPresenter.statusText(statusContext(for: runtime))
    }

    static func incompleteInstallStatusText(for runtime: Runtime, installState: RuntimeInstallState) -> String? {
        LocalRuntimeStatusPresenter.incompleteInstallStatusText(
            descriptor: runtime.localRuntimeDescriptor,
            installState: installState
        )
    }

    static func statusContext(for runtime: Runtime) -> LocalRuntimeStatusContext {
        LocalRuntimeStatusContext(
            descriptor: runtime.localRuntimeDescriptor,
            installState: runtimeInstallState(for: runtime),
            isSupported: runtime.isSupportedOnCurrentSystem,
            isDownloading: isDownloading(runtime),
            isPaused: isPaused(runtime),
            downloadFailureMessage: SpeechRuntimeDownloadFailureStore.failure(for: runtime)?.message,
            inferenceFailureText: inferenceFailureStatusText(for: runtime)
        )
    }

    private static func inferenceFailureStatusText(for runtime: Runtime) -> String? {
        guard let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime) else { return nil }
        let context = SpeechRuntimeInferenceFailureStore.contextTitle(failure.context)
        let time = SpeechRuntimeInferenceFailureStore.relativeTimeText(since: failure.timestamp)
        return AppText.localized(
            "\(context)：\(failure.message) · \(time)",
            "\(context): \(failure.message) · \(time)"
        )
    }
}
