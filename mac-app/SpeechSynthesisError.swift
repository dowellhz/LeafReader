import Foundation

enum SpeechSynthesisError: Error, Equatable {
    case runtimeUnavailable(String)
    case voiceUnavailable(String)
    case workerStartFailed(String)
    case workerTimedOut(String)
    case processFailed(String)
    case dependencyMissing(String)
    case modelLoadFailed(String)
    case permissionDenied(String)
    case portUnavailable(String)
    case invalidAudioOutput(String)
    case outputWriteFailed(String)
    case unsupportedLanguage(String)

    var localizedDescription: String {
        switch self {
        case .runtimeUnavailable(let runtime):
            return AppText.localized(
                "\(runtime) 运行库不可用。请重新安装或更新应用。",
                "\(runtime) runtime is unavailable. Reinstall or update the app."
            )
        case .voiceUnavailable(let runtime):
            return AppText.localized(
                "\(runtime) 声音或模型文件缺失。请在朗读设置里重新下载模型。",
                "\(runtime) voice or model files are missing. Download the model again in Read Aloud settings."
            )
        case .workerStartFailed(let runtime):
            return AppText.localized(
                "\(runtime) 朗读引擎启动失败。请重启应用；如果仍失败，请重新安装或更新应用。",
                "\(runtime) speech engine failed to start. Restart the app; if it still fails, reinstall or update the app."
            )
        case .workerTimedOut(let runtime):
            return AppText.localized(
                "\(runtime) 推理超时。请稍后重试，或切换到其他朗读模型。",
                "\(runtime) inference timed out. Try again later or switch to another speech model."
            )
        case .processFailed(let runtime):
            return AppText.localized(
                "\(runtime) 推理进程异常退出。请重启应用；如果仍失败，请重新下载模型。",
                "\(runtime) inference process exited unexpectedly. Restart the app; if it still fails, download the model again."
            )
        case .dependencyMissing(let runtime):
            return AppText.localized(
                "\(runtime) 运行依赖缺失或动态库无法加载。请重新安装或更新应用。",
                "\(runtime) is missing a runtime dependency or could not load a dynamic library. Reinstall or update the app."
            )
        case .modelLoadFailed(let runtime):
            return AppText.localized(
                "\(runtime) 模型或声音配置加载失败。请在朗读设置里重新下载模型。",
                "\(runtime) failed to load its model or voice configuration. Download the model again in Read Aloud settings."
            )
        case .permissionDenied(let runtime):
            return AppText.localized(
                "\(runtime) 没有权限运行或写入音频文件。请重新安装应用，或检查文件权限。",
                "\(runtime) does not have permission to run or write audio files. Reinstall the app or check file permissions."
            )
        case .portUnavailable(let runtime):
            return AppText.localized(
                "\(runtime) 本地朗读服务端口不可用。请重启应用后再试。",
                "\(runtime) local speech server port is unavailable. Restart the app and try again."
            )
        case .invalidAudioOutput(let runtime):
            return AppText.localized(
                "\(runtime) 没有生成有效音频。请重试，或在朗读设置里重新下载模型。",
                "\(runtime) did not generate valid audio. Try again, or download the model again in Read Aloud settings."
            )
        case .outputWriteFailed(let runtime):
            return AppText.localized(
                "\(runtime) 无法写入朗读音频文件。请检查磁盘空间后重试。",
                "\(runtime) could not write the speech audio file. Check disk space and try again."
            )
        case .unsupportedLanguage(let runtime):
            return AppText.localized(
                "\(runtime) 不支持当前文本语言。请切换到支持该语言的朗读模型。",
                "\(runtime) does not support this text language. Switch to a speech model that supports it."
            )
        }
    }

    var supportsRedownload: Bool {
        switch self {
        case .voiceUnavailable, .modelLoadFailed, .invalidAudioOutput:
            return true
        case .runtimeUnavailable, .workerStartFailed, .workerTimedOut, .processFailed,
             .dependencyMissing, .permissionDenied, .portUnavailable, .outputWriteFailed,
             .unsupportedLanguage:
            return false
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .voiceUnavailable, .modelLoadFailed, .invalidAudioOutput:
            return AppText.localized("重新下载该模型", "Download Model Again")
        case .workerTimedOut:
            return AppText.localized("切换模型", "Switch Model")
        case .dependencyMissing, .runtimeUnavailable, .workerStartFailed:
            return AppText.localized("打开朗读设置", "Open Read Aloud Settings")
        case .permissionDenied, .outputWriteFailed:
            return AppText.localized("打开朗读设置", "Open Read Aloud Settings")
        case .portUnavailable, .processFailed, .unsupportedLanguage:
            return AppText.localized("打开朗读设置", "Open Read Aloud Settings")
        }
    }

    var diagnosticKind: String {
        switch self {
        case .runtimeUnavailable:
            return "runtimeUnavailable"
        case .voiceUnavailable:
            return "voiceUnavailable"
        case .workerStartFailed:
            return "workerStartFailed"
        case .workerTimedOut:
            return "workerTimedOut"
        case .processFailed:
            return "processFailed"
        case .dependencyMissing:
            return "dependencyMissing"
        case .modelLoadFailed:
            return "modelLoadFailed"
        case .permissionDenied:
            return "permissionDenied"
        case .portUnavailable:
            return "portUnavailable"
        case .invalidAudioOutput:
            return "invalidAudioOutput"
        case .outputWriteFailed:
            return "outputWriteFailed"
        case .unsupportedLanguage:
            return "unsupportedLanguage"
        }
    }

    static func classifiedProcessFailure(
        runtime: String,
        diagnostic: String,
        timedOut: Bool = false
    ) -> SpeechSynthesisError {
        if timedOut {
            return .workerTimedOut(runtime)
        }
        let normalized = diagnostic.lowercased()
        if normalized.contains("library not loaded")
            || normalized.contains("dyld")
            || normalized.contains("image not found")
            || normalized.contains("no lc_rpath")
            || normalized.contains("symbol not found") {
            return .dependencyMissing(runtime)
        }
        if normalized.contains("permission denied")
            || normalized.contains("operation not permitted")
            || normalized.contains("not executable") {
            return .permissionDenied(runtime)
        }
        if normalized.contains("address already in use")
            || normalized.contains("port")
            || normalized.contains("bind") {
            return .portUnavailable(runtime)
        }
        if normalized.contains("onnx")
            || normalized.contains("model")
            || normalized.contains("config")
            || normalized.contains("voice")
            || normalized.contains("failed to load")
            || normalized.contains("no such file") {
            return .modelLoadFailed(runtime)
        }
        return .processFailed(runtime)
    }
}

extension Result where Failure == SpeechSynthesisError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
