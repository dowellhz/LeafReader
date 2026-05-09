import Foundation

struct ChatMessage {
    let role: String
    let content: String
}

struct TranscriptEntry {
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

    static var askAI: String { localized("✨ 问 AI", "✨ Ask AI") }
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
    static var noPDF: String { localized("No PDF", "No PDF") }
    static var fullScreen: String { localized("全屏", "Full Screen") }
    static var windowed: String { localized("窗口", "Windowed") }
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

    static func systemPrompt() -> String {
        if isChinese {
            return """
            你是一名英语学习助手。

            规则如下：

            如果用户输入的是单个单词或短词组：
            解释中文意思
            说明词性（如名词、动词、形容词等）
            给 1～2 个简单自然的英文例句
            不需要过度展开

            如果用户输入的是完整句子或长段落：
            按句子或自然语义块逐段处理
            每段先输出原文，原文必须单独一行并用 Markdown 粗体格式 **原文** 包起来
            再给出自然中文翻译
            再解析其中较难的单词、短语、俚语或固定搭配
            简单基础词汇无需解释
            重点解释地道表达、固定搭配、语法难点、文化语境

            输出风格：
            简洁清晰
            不要长篇英语语法教学
            优先帮助用户“看懂”和“会用”
            默认以美式日常英语为主进行解释
            """
        }
        return """
        You are an English reading and vocabulary assistant.

        Rules:

        If the user provides a single word or short phrase:
        Explain the meaning in clear English.
        Include the part of speech.
        Give 1-2 simple, natural English examples.
        Keep the answer concise.

        If the user provides a full sentence or longer passage:
        Process it by sentence or natural meaning block.
        First output the original source text on its own line, wrapped in Markdown bold like **Original text**.
        Then give a plain-English explanation or paraphrase.
        Then explain difficult words, phrases, idioms, grammar points, and cultural context.
        Do not explain very basic words.

        Style:
        Be concise and practical.
        Focus on helping the user understand and use the English naturally.
        Prefer everyday American English explanations.
        """
    }

    static func wordPrompt(for word: String, context: String = "") -> String {
        if isChinese {
            return """
            翻译下单词：\(word)

            这个词在文章中的上下文：
            \(context.isEmpty ? "（无）" : context)

            必须严格按下面 Markdown 格式输出，内容简洁，不要额外展开：

            # \(word)

            ## 发音：

            * 英 /.../
            * 美 /.../

            意思：中文核心意思；常见引申义

            ## 常见用法：

            ### 1. 用法名称

            * English example.

              （中文翻译）

            ### 2. 用法名称

            * English example.

              （中文翻译）

            ### 3. 用法名称

            * English example.

              （中文翻译）

            ## 词性：

            * 词性中文（part of speech）

            要求：
            - 必须优先结合上下文解释这个词在原文里的意思
            - 如果有多个常见词性，可以列出多个
            - 音标必须放在最前面，紧跟单词标题后
            - 例句要自然、简单、贴近日常使用
            - 默认以美式日常英语为主
            - 不要使用 Markdown 表格
            """
        }
        return """
        Explain this word: \(word)

        Context from the article:
        \(context.isEmpty ? "(None)" : context)

        Use this exact Markdown structure. Keep it concise:

        # \(word)

        ## Pronunciation:

        * UK /.../
        * US /.../

        Meaning: core meaning and common extended meanings

        ## Common uses:

        ### 1. Use name

        * English example.

          Short explanation.

        ### 2. Use name

        * English example.

          Short explanation.

        ### 3. Use name

        * English example.

          Short explanation.

        ## Part of speech:

        * part of speech

        Requirements:
        - Prioritize the meaning of this word in the article context.
        - List multiple common parts of speech when needed.
        - Put pronunciation first, directly after the word title.
        - Use natural, simple, everyday examples.
        - Prefer everyday American English.
        - Do not use Markdown tables.
        """
    }

    static func sentencePrompt(for text: String) -> String {
        if isChinese {
            return """
            你是英语老师，翻译下那段文字。

            格式要求：
            - 按句子或自然语义块逐段处理
            - 每段先放原文，原文必须单独一行并用 Markdown 粗体格式 **原文** 包起来
            - 下一行放自然中文翻译
            - 然后用 Markdown 项目符号解释重点词、短语、固定搭配、文化背景
            - 项目符号格式使用：* xxx：解释
            - 重要补充说明也用 Markdown 项目符号，不要写成长段
            - 不解释简单基础词
            - 不要长篇语法教学
            - 不要使用 Markdown 表格

            需要翻译和解释的英文：

            \(text)
            """
        }
        return """
        You are an English teacher. Explain this passage.

        Format requirements:
        - Process it by sentence or natural meaning block.
        - Put the original source text first, on its own line, wrapped in Markdown bold like **Original text**.
        - On the next line, give a natural plain-English explanation or paraphrase.
        - Then use Markdown bullets to explain important words, phrases, idioms, grammar, or cultural context.
        - Use bullet format: * xxx: explanation
        - Keep explanations concise.
        - Do not explain very basic words.
        - Do not use Markdown tables.

        English text to explain:

        \(text)
        """
    }

    static func followUpPrompt(context: String, text: String) -> String {
        if isChinese {
            return """
            下面是右侧 AI view 里已经展示给用户的上下文。请把它作为本次继续追问的上下文来回答，不要重复整段历史，除非用户明确要求。

            【AI view 上下文】
            \(context)

            【用户继续追问】
            \(text)
            """
        }
        return """
        Below is the context already shown in the AI view. Use it as context for this follow-up answer. Do not repeat the full history unless the user asks.

        [AI view context]
        \(context)

        [User follow-up]
        \(text)
        """
    }
}
