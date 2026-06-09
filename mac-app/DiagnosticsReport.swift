import Foundation
import Sparkle

struct DiagnosticRow {
    let title: String
    let detail: String
    let isOK: Bool
}

enum DiagnosticsReport {
    static func rows(
        updater: SPUUpdater?,
        controller: ReaderWindowController?
    ) -> [DiagnosticRow] {
        let selectedModel = AISettingsStore.selectedModel
        let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID)
        let runnableRuntime = SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID)
        let documentName = controller?.currentFileURL?.lastPathComponent ?? AppText.noPDF
        let ecdict = ECDICTDictionary.shared.diagnosticInfo()
        let appcastURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "-"
        let launchPerformance = LaunchPerformanceTracker.shared.snapshot()

        return [
            DiagnosticRow(
                title: AppText.localized("应用版本", "App Version"),
                detail: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"))",
                isOK: true
            ),
            DiagnosticRow(
                title: AppText.localized("运行路径", "Runtime Path"),
                detail: Bundle.main.bundleURL.path,
                isOK: true
            ),
            DiagnosticRow(
                title: AppText.localized("启动耗时", "Launch Time"),
                detail: launchPerformance?.detailText ?? AppText.localized("暂无数据", "No data yet"),
                isOK: launchPerformance != nil
            ),
            DiagnosticRow(
                title: AppText.localized("Sparkle 更新", "Sparkle Updates"),
                detail: updater?.canCheckForUpdates == true
                    ? AppText.localized("可检查更新", "Can check for updates")
                    : AppText.localized("暂不可检查更新", "Cannot check right now"),
                isOK: updater?.canCheckForUpdates == true
            ),
            DiagnosticRow(
                title: AppText.localized("Appcast", "Appcast"),
                detail: appcastURL,
                isOK: appcastURL.hasPrefix("https://")
            ),
            DiagnosticRow(
                title: AppText.localized("网络", "Network"),
                detail: NetworkConnectivityMonitor.shared.isOnline
                    ? AppText.localized("在线", "Online")
                    : AppText.localized("离线", "Offline"),
                isOK: NetworkConnectivityMonitor.shared.isOnline
            ),
            DiagnosticRow(
                title: AppText.localized("模型", "Model"),
                detail: AISettingsStore.hasAPIKeyForSelectedModel
                    ? "\(selectedModel.displayName) · API Key OK"
                    : "\(selectedModel.displayName) · \(AppText.localized("未配置 API Key", "API Key missing"))",
                isOK: AISettingsStore.hasAPIKeyForSelectedModel
            ),
            DiagnosticRow(
                title: AppText.localized("本地词典", "Local Dictionary"),
                detail: ecdict.detailText,
                isOK: ecdict.isInstalled
            ),
            DiagnosticRow(
                title: AppText.localized("朗读运行时", "Speech Runtime"),
                detail: runnableRuntime != nil
                    ? "\(runtime?.title ?? AISettingsStore.selectedSpeechRuntimeID) · \(speechRuntimeDetail(runtime))"
                    : "\(runtime?.title ?? AISettingsStore.selectedSpeechRuntimeID) · \(AppText.localized("不可用", "Unavailable"))",
                isOK: runnableRuntime != nil
            ),
            DiagnosticRow(
                title: AppText.localized("当前文档", "Current Document"),
                detail: documentName,
                isOK: controller?.currentFileURL != nil
            )
        ]
    }

    static func pasteboardText(rows: [DiagnosticRow]) -> String {
        rows
            .map { "\($0.isOK ? "OK" : "WARN")\t\($0.title)\t\($0.detail)" }
            .joined(separator: "\n")
    }

    private static func speechRuntimeDetail(_ runtime: SpeechRuntimeResourceManager.Runtime?) -> String {
        guard let runtime else { return "OK" }
        let directoryURL = runtime.installDirectories.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? runtime.installDirectory
        let size = directorySizeText(directoryURL)
        return size.isEmpty ? "OK · \(directoryURL.path)" : "OK · \(size) · \(directoryURL.path)"
    }

    private static func directorySizeText(_ url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        guard total > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
