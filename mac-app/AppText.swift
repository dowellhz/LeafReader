import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct TranscriptEntry: Codable {
    let role: String
    let content: String
}

enum AppText {
    enum Language: String, CaseIterable {
        case system
        case chinese
        case english

        var title: String {
            switch self {
            case .system:
                return AppText.localized("跟随系统", "System")
            case .chinese:
                return "中文"
            case .english:
                return "English"
            }
        }
    }

    static let languageDefaultsKey = "appLanguage"

    static var selectedLanguage: Language {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: languageDefaultsKey),
                  let language = Language(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var isChinese: Bool {
        switch selectedLanguage {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        case .chinese:
            return true
        case .english:
            return false
        }
    }

    static func localized(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    static var askAI: String { localized("✨ 学英语", "✨ Learn English") }
    static var explainPrefix: String { localized("解释", "Explain") }
    static var userRole: String { localized("我", "Me") }
    static var aiRole: String { "AI" }
    static var errorRole: String { localized("错误", "Error") }
    static var none: String { localized("（暂无）", "(None)") }
    static var thinking: String { localized("正在思考...", "Thinking...") }
    static var generating: String { localized("正在生成...", "Generating...") }
    static var tapToExpand: String { localized("点击展开/收起", "Click to expand/collapse") }
    static var followUpPlaceholder: String { localized("继续追问", "Ask a follow-up") }
    static var send: String { localized("发送", "Send") }
    static var noPDF: String { localized("没有加载书籍", "No book loaded") }
    static var fullScreen: String { localized("全屏", "Full") }
    static var windowed: String { localized("窗口", "Window") }
    static var cover: String { localized("首页", "Cover") }
    static var prev: String { localized("上一页", "Prev") }
    static var next: String { localized("下一页", "Next") }
    static var settings: String { localized("设置", "Settings") }
    static var close: String { localized("关闭", "Close") }
    static var model: String { localized("模型", "Model") }
    static var modelHelp: String { localized("选择你要使用的 AI 模型。", "Choose the AI model you want to use.") }
    static var language: String { localized("语言", "Language") }
    static var languageHelp: String { localized("选择界面语言和 AI 回答语言。", "Choose the UI language and AI response language.") }
    static var apiKeyPlaceholder: String { localized("请输入你的 API Key", "Enter your API Key") }
    static var keyHelp: String {
        localized("你的 API Key 将安全存储，仅用于你自己的请求。", "Your API Key is stored locally and only used for your own requests.")
    }
    static var showAPIKey: String { localized("显示 API Key", "Show API Key") }
    static var hideAPIKey: String { localized("隐藏 API Key", "Hide API Key") }
    static var cancel: String { localized("取消", "Cancel") }
    static var confirm: String { localized("确认", "Confirm") }
}
