import Foundation

extension SpeechRuntimeResourceManager {
    enum RuntimeInstallState: Equatable {
        case complete
        case missingRuntime
        case missingModel
        case missingRuntimeAndModel
    }

    static func isDownloaded(_ runtime: Runtime) -> Bool {
        runtimeInstallState(for: runtime) == .complete
    }

    static func runtimeInstallState(for runtime: Runtime) -> RuntimeInstallState {
        let hasRuntime: Bool
        let hasModel: Bool
        switch runtime {
        case .kitten:
            hasRuntime = runtime.installDirectories.contains { directory in
                kittenRuntimePathsExist(in: directory)
            }
            hasModel = runtime.installDirectories.contains { directory in
                kittenModelPathsExist(in: directory)
            }
        case .kokoro:
            hasRuntime = runtime.installDirectories.contains { directory in
                FileManager.default.isExecutableFile(atPath: Runtime.kokoro.executableURL(in: directory).path)
            }
            hasModel = kokoroAneModelCacheExists()
        case .piper:
            hasRuntime = runtime.installDirectories.contains { directory in
                piperRuntimePathsExist(in: directory)
            }
            hasModel = piperAnyVoicePathsExist()
        }

        return runtimeInstallState(hasRuntime: hasRuntime, hasModel: hasModel)
    }

    static func runtimeInstallState(hasRuntime: Bool, hasModel: Bool) -> RuntimeInstallState {
        switch (hasRuntime, hasModel) {
        case (true, true):
            return .complete
        case (false, true):
            return .missingRuntime
        case (true, false):
            return .missingModel
        case (false, false):
            return .missingRuntimeAndModel
        }
    }

    static func isRunnable(_ runtime: Runtime) -> Bool {
        runtime.isSupportedOnCurrentSystem && isDownloaded(runtime)
    }

    static func availabilityText(for runtime: Runtime) -> String? {
        availabilityText(
            isSupported: runtime.isSupportedOnCurrentSystem,
            downloaded: isDownloaded(runtime),
            minimumSystemVersionText: runtime.minimumSystemVersionText
        )
    }

    static func availabilityText(isSupported: Bool, downloaded: Bool, minimumSystemVersionText: String) -> String? {
        guard !(isSupported && downloaded) else { return nil }
        if !isSupported {
            return AppText.localized(
                "需要 \(minimumSystemVersionText)",
                "Requires \(minimumSystemVersionText)"
            )
        }
        if downloaded {
            return AppText.localized("文件不完整", "Incomplete files")
        }
        return AppText.localized("未下载", "Not downloaded")
    }

    static func runnableRuntime(preferredID: String) -> Runtime? {
        if let preferred = Runtime.runtime(for: preferredID),
           isRunnable(preferred) {
            return preferred
        }
        return runnableReadAloudRuntimes().first
    }

    static func runnableReadAloudRuntimes() -> [Runtime] {
        Runtime.displayOrder.filter { runtime in
            isRunnable(runtime)
        }
    }

    static func statusText(for runtime: Runtime) -> String {
        let size = runtime.downloadSizeText
        let summary = runtime.summaryText
        let installState = runtimeInstallState(for: runtime)
        if isDownloading(runtime) {
            if isPaused(runtime) {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if !runtime.isSupportedOnCurrentSystem {
            if installState == .complete {
                return AppText.localized(
                    "已下载 · 需要 \(runtime.minimumSystemVersionText) 或更高",
                    "Downloaded · Requires \(runtime.minimumSystemVersionText) or later"
                )
            }
            if let failure = SpeechRuntimeDownloadFailureStore.failure(for: runtime) {
                return AppText.localized(
                    "未下载 · \(summary) · 需要 \(runtime.minimumSystemVersionText) 或更高 · \(size) · 上次失败：\(failure.message)",
                    "Not downloaded · \(summary) · Requires \(runtime.minimumSystemVersionText) or later · \(size) · Last failed: \(failure.message)"
                )
            }
            return AppText.localized(
                "未下载 · \(summary) · 需要 \(runtime.minimumSystemVersionText) 或更高 · \(size)",
                "Not downloaded · \(summary) · Requires \(runtime.minimumSystemVersionText) or later · \(size)"
            )
        }
        if installState == .complete {
            if let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime) {
                let context = SpeechRuntimeInferenceFailureStore.contextTitle(failure.context)
                let time = SpeechRuntimeInferenceFailureStore.relativeTimeText(since: failure.timestamp)
                return AppText.localized(
                    "已安装 · \(size) · \(context)：\(failure.message) · \(time)",
                    "Installed · \(size) · \(context): \(failure.message) · \(time)"
                )
            }
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        if let text = incompleteInstallStatusText(for: runtime, installState: installState) {
            return text
        }
        if let failure = SpeechRuntimeDownloadFailureStore.failure(for: runtime) {
            return AppText.localized(
                "未下载 · \(summary) · \(size) · 上次失败：\(failure.message)",
                "Not downloaded · \(summary) · \(size) · Last failed: \(failure.message)"
            )
        }
        return AppText.localized("未下载 · \(summary) · \(size)", "Not downloaded · \(summary) · \(size)")
    }

    static func incompleteInstallStatusText(for runtime: Runtime, installState: RuntimeInstallState) -> String? {
        let size = runtime.downloadSizeText
        switch installState {
        case .missingRuntime:
            return AppText.localized(
                "缺少运行时 · 模型已安装 · \(size)",
                "Missing runtime · Model installed · \(size)"
            )
        case .missingModel:
            return nil
        case .missingRuntimeAndModel:
            return nil
        case .complete:
            return nil
        }
    }
}
