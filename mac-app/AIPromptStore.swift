import Foundation

enum AIPromptStore {
    private struct PromptLanguageConfig: Decodable {
        let system: String
        let word: String
        let sentence: String
        let summary: String
        let translation: String
        let followUp: String
        let selectedFollowUp: String
        let readingFollowUp: String
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

    static func translationPrompt(title: String, text: String) -> String {
        render(languageConfig.translation, values: ["title": title, "text": text])
    }

    static func followUpPrompt(context: String, text: String) -> String {
        render(languageConfig.followUp, values: ["context": context, "text": text])
    }

    static func selectedFollowUpPrompt(selectedText: String, context: String, question: String) -> String {
        render(
            languageConfig.selectedFollowUp,
            values: [
                "selectedText": selectedText,
                "context": context.isEmpty ? localizedNone : context,
                "question": question
            ]
        )
    }

    static func readingFollowUpPrompt(readingText: String, context: String, question: String) -> String {
        render(
            languageConfig.readingFollowUp,
            values: [
                "readingText": readingText,
                "context": context.isEmpty ? localizedNone : context,
                "question": question
            ]
        )
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
            translation: "请把下面内容翻译成自然中文。目标语言：简体中文。只输出中文译文，不要输出英文原文，不要复述原文。除人名、地名、书名、机构名等专有名词外，所有英文句子都必须翻译成中文。每个非空段落开头空两格。不要分析、解释、总结，也不要添加标题或多余说明，不要使用 Markdown 或 **粗体** 标记。严格保持原文段落结构和换行位置，不要合并段落，也不要额外拆分段落。\n\n{{text}}",
            followUp: "下面是 AI view 上下文：\n{{context}}\n\n用户继续追问：\n{{text}}",
            selectedFollowUp: "用户选中了下面这段文字，并提出了问题。请优先结合选中文字回答。只回答用户问题，不要自动追加关键词翻译，不要自动解释单词、短语或语法，除非用户问题明确要求，不要套用单词解释模板。\n\n【选中文字】\n{{selectedText}}\n\n【附近上下文】\n{{context}}\n\n【用户问题】\n{{question}}",
            readingFollowUp: "用户没有选中文字，正在基于当前阅读区提问。请结合当前阅读内容和 AI view 最近上下文回答用户问题。只回答用户问题，不要自动翻译整段，不要自动总结，除非用户明确要求。\n\n【当前阅读内容】\n{{readingText}}\n\n【AI view 最近上下文】\n{{context}}\n\n【用户问题】\n{{question}}"
        ),
        en: PromptLanguageConfig(
            system: "You are an English reading and vocabulary assistant. Be concise and practical.",
            word: "Explain this word: {{word}}\n\nContext from the article:\n{{context}}",
            sentence: "Explain this English passage:\n\n{{text}}",
            summary: "Summarize the current reading content:\n\nTitle: {{title}}\n\nText:\n{{text}}",
            translation: "Translate the following content into clear, natural English. Output only the translation. Do not analyze, explain, summarize, add a title, add extra notes, or use Markdown or **bold** markers. Strictly preserve the original paragraph structure and line breaks. Do not merge paragraphs or split them into extra paragraphs.\n\n{{text}}",
            followUp: "AI view context:\n{{context}}\n\nUser follow-up:\n{{text}}",
            selectedFollowUp: "The user selected the following passage and asked a question. Answer primarily based on the selected text. Answer only the user question. Do not automatically add keyword translations or word, phrase, or grammar explanations unless explicitly asked. Do not use the vocabulary explanation template.\n\n[Selected text]\n{{selectedText}}\n\n[Nearby context]\n{{context}}\n\n[User question]\n{{question}}",
            readingFollowUp: "The user did not select text and is asking about the current reading area. Answer using the current reading text and the recent AI view context. Answer only the user question. Do not automatically translate or summarize the whole passage unless explicitly asked.\n\n[Current reading text]\n{{readingText}}\n\n[Recent AI view context]\n{{context}}\n\n[User question]\n{{question}}"
        )
    )
}
