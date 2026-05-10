import Foundation

enum AIPromptStore {
    private struct PromptLanguageConfig: Decodable {
        let system: String
        let word: String
        let sentence: String
        let summary: String
        let followUp: String
    }

    private struct PromptConfig: Decodable {
        let zh: PromptLanguageConfig
        let en: PromptLanguageConfig
    }

    private static let configFileName = "AIPrompts"
    private static let configFileExtension = "json"

    private static var config: PromptConfig = loadConfig()

    static func systemPrompt() -> String {
        languageConfig.system
    }

    static func wordPrompt(for word: String, context: String = "") -> String {
        render(
            languageConfig.word,
            values: [
                "word": word,
                "context": context.isEmpty ? localizedNone : context
            ]
        )
    }

    static func sentencePrompt(for text: String) -> String {
        render(languageConfig.sentence, values: ["text": text])
    }

    static func summaryPrompt(title: String, text: String) -> String {
        render(languageConfig.summary, values: ["title": title, "text": text])
    }

    static func followUpPrompt(context: String, text: String) -> String {
        render(languageConfig.followUp, values: ["context": context, "text": text])
    }

    private static var languageConfig: PromptLanguageConfig {
        AppText.isChinese ? config.zh : config.en
    }

    private static var localizedNone: String {
        AppText.isChinese ? "（无）" : "(None)"
    }

    private static func render(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { result, item in
            result.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }

    private static func loadConfig() -> PromptConfig {
        let decoder = JSONDecoder()
        for url in candidateConfigURLs() {
            guard let data = try? Data(contentsOf: url),
                  let config = try? decoder.decode(PromptConfig.self, from: data) else {
                continue
            }
            return config
        }
        return fallbackConfig
    }

    private static func candidateConfigURLs() -> [URL] {
        var urls: [URL] = []
        if let bundledURL = Bundle.main.url(forResource: configFileName, withExtension: configFileExtension) {
            urls.append(bundledURL)
        }
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(currentDirectoryURL.appendingPathComponent("mac-app/\(configFileName).\(configFileExtension)"))
        urls.append(currentDirectoryURL.appendingPathComponent("\(configFileName).\(configFileExtension)"))
        return urls
    }

    private static let fallbackConfig = PromptConfig(
        zh: PromptLanguageConfig(
            system: "你是一名英语学习助手。回答要简洁清晰，优先帮助用户看懂和会用。",
            word: "翻译下单词：{{word}}\n\n这个词在文章中的上下文：\n{{context}}",
            sentence: "你是英语老师，翻译并解释下面这段英文：\n\n{{text}}",
            summary: "请总结下面的当前阅读内容：\n\n标题：{{title}}\n\n正文：\n{{text}}",
            followUp: "下面是 AI view 上下文：\n{{context}}\n\n用户继续追问：\n{{text}}"
        ),
        en: PromptLanguageConfig(
            system: "You are an English reading and vocabulary assistant. Be concise and practical.",
            word: "Explain this word: {{word}}\n\nContext from the article:\n{{context}}",
            sentence: "Explain this English passage:\n\n{{text}}",
            summary: "Summarize the current reading content:\n\nTitle: {{title}}\n\nText:\n{{text}}",
            followUp: "AI view context:\n{{context}}\n\nUser follow-up:\n{{text}}"
        )
    )
}
