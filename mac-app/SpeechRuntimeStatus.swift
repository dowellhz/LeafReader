import Foundation

extension SpeechRuntimeResourceManager {
    static func isDownloaded(_ runtime: Runtime) -> Bool {
        if runtime == .kitten {
            return runtime.installDirectories.contains { directory in
                kittenRuntimePathsExist(in: directory)
            } && runtime.installDirectories.contains { directory in
                kittenModelPathsExist(in: directory)
            }
        }
        if runtime == .kokoro {
            return runtime.installDirectories.contains { directory in
                FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("fluidaudiocli").path)
            } && kokoroAneModelCacheExists()
        }
        if runtime == .piper {
            return runtime.installDirectories.contains { directory in
                piperRuntimePathsExist(in: directory)
            } && piperVoicePathsExist()
        }
        return runtime.installDirectories.contains { directory in
            requiredPathsExist(runtime.requiredPaths(in: directory))
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
        if isDownloading(runtime) {
            if isPaused(runtime) {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if !runtime.isSupportedOnCurrentSystem {
            if isDownloaded(runtime) {
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
        if isRunnable(runtime) {
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        if let failure = SpeechRuntimeDownloadFailureStore.failure(for: runtime) {
            return AppText.localized(
                "未下载 · \(summary) · \(size) · 上次失败：\(failure.message)",
                "Not downloaded · \(summary) · \(size) · Last failed: \(failure.message)"
            )
        }
        return AppText.localized("未下载 · \(summary) · \(size)", "Not downloaded · \(summary) · \(size)")
    }
}
