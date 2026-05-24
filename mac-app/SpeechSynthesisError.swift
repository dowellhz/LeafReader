import Foundation

enum SpeechSynthesisError: Error, Equatable {
    case runtimeUnavailable(String)
    case voiceUnavailable(String)
    case workerStartFailed(String)
    case workerTimedOut(String)
    case processFailed(String)
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
}

extension Result where Failure == SpeechSynthesisError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
