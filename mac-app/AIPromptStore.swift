import Foundation

enum AIPromptStore {
    private struct PromptLanguageConfig: Decodable {
        let system: String
        let compactSystem: String
        let word: String
        let sentence: String
        let difficultSentence: String
        let summary: String
        let translation: String
        let followUp: String
        let readingFollowUp: String
        let documentAgent: String

        private enum CodingKeys: String, CodingKey {
            case system
            case compactSystem
            case legacySystem2 = "system2"
            case word
            case sentence
            case difficultSentence
            case summary
            case translation
            case followUp
            case readingFollowUp
            case documentAgent
        }

        init(
            system: String,
            compactSystem: String,
            word: String,
            sentence: String,
            difficultSentence: String,
            summary: String,
            translation: String,
            followUp: String,
            readingFollowUp: String,
            documentAgent: String
        ) {
            self.system = system
            self.compactSystem = compactSystem
            self.word = word
            self.sentence = sentence
            self.difficultSentence = difficultSentence
            self.summary = summary
            self.translation = translation
            self.followUp = followUp
            self.readingFollowUp = readingFollowUp
            self.documentAgent = documentAgent
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            system = try container.decode(String.self, forKey: .system)
            compactSystem = try container.decodeIfPresent(String.self, forKey: .compactSystem)
                ?? container.decodeIfPresent(String.self, forKey: .legacySystem2)
                ?? system
            word = try container.decode(String.self, forKey: .word)
            sentence = try container.decode(String.self, forKey: .sentence)
            difficultSentence = try container.decodeIfPresent(String.self, forKey: .difficultSentence)
                ?? sentence
            summary = try container.decode(String.self, forKey: .summary)
            translation = try container.decode(String.self, forKey: .translation)
            followUp = try container.decode(String.self, forKey: .followUp)
            readingFollowUp = try container.decode(String.self, forKey: .readingFollowUp)
            documentAgent = try container.decode(String.self, forKey: .documentAgent)
        }
    }

    private struct PromptConfig: Decodable {
        let zh: PromptLanguageConfig
        let en: PromptLanguageConfig
    }

    private static let configFileName = "AIPrompts"
    private static let configFileExtension = "json"

    private static var config: PromptConfig = loadConfig()

    static func systemPrompt() -> String {
        promptWithResponseLanguageInstruction(languageConfig.system)
    }

    static func compactSystemPrompt() -> String {
        promptWithResponseLanguageInstruction(languageConfig.compactSystem)
    }

    static func wordPrompt(for word: String, context: String = "") -> String {
        return render(
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

    static func difficultSentencePrompt(for text: String) -> String {
        render(languageConfig.difficultSentence, values: ["text": text])
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

    static func documentAgentPrompt(
        title: String,
        question: String,
        questionSubject: String = "",
        currentPageText: String,
        chapterText: String,
        searchResults: String,
        context: String,
        currentTextTitle: String? = nil,
        nearbyTextTitle: String? = nil
    ) -> String {
        let currentTitle = currentTextTitle ?? (AppText.isChinese ? "当前页内容" : "Current page text")
        let nearbyTitle = nearbyTextTitle ?? (AppText.isChinese ? "当前章节或附近页面" : "Current chapter or nearby pages")
        return render(
            languageConfig.documentAgent,
            values: [
                "title": title,
                "question": question,
                "questionLine": documentAgentQuestionLine(
                    title: title,
                    question: question,
                    questionSubject: questionSubject
                ),
                "currentPageSection": optionalSection(title: currentTitle, body: currentPageText),
                "chapterSection": optionalSection(title: nearbyTitle, body: chapterText),
                "searchResultsSection": optionalSection(title: AppText.isChinese ? "文档检索结果" : "Document search results", body: searchResults),
                "context": context.isEmpty ? localizedNone : context
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
        promptWithResponseLanguageInstruction(values.reduce(template) { result, item in
            result.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        })
    }

    private static func promptWithResponseLanguageInstruction(_ prompt: String) -> String {
        guard !AppText.isChinese else { return prompt }
        return """
        \(prompt)

        Response language: answer in English regardless of the language of the source text, selected text, document context, retrieved evidence, or conversation history, unless the user explicitly asks for another language.
        """
    }

    private static func optionalSection(title: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return AppText.isChinese ? "【\(title)】\n\(trimmed)\n" : "[\(title)]\n\(trimmed)\n"
    }

    private static func documentAgentQuestionLine(title: String, question: String, questionSubject: String) -> String {
        let subject = questionSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            return AppText.isChinese
                ? "我正在读《\(title)》。用户有如下问题：\(question)"
                : "I am reading \(title). The user asks: \(question)"
        }
        return AppText.isChinese
            ? "我正在读《\(title)》。用户关于\(subject)有如下问题：\(question)"
            : "I am reading \(title). The user has a question about \(subject): \(question)"
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
            compactSystem: "你是一名英语阅读和词汇助手。回答要紧凑：不要连续空行，不要大段铺开，除非用户要求展开。",
            word: "翻译下单词：{{word}}\n\n这个词在文章中的上下文：\n{{context}}\n\n输出要求：不要在回答第一行重复输出单词标题，直接从发音开始。",
            sentence: "你是英语老师，翻译并解释下面这段英文：\n\n{{text}}",
            difficultSentence: "请解析下面英文难句，输出紧凑 Markdown，不要连续空行，不要 Markdown 表格。\n必须包含：\n## 句子结构拆解\n## 主谓宾、从句、修饰关系\n## 逐层翻译\n## 常见表达解释\n## 为什么这么写\n\n【英文】\n{{text}}",
            summary: "请总结下面的当前阅读内容：\n\n标题：{{title}}\n\n正文：\n{{text}}",
            translation: "请把下面内容翻译成自然中文。目标语言：简体中文。只输出中文译文，不要输出英文原文，不要复述原文。除人名、地名、书名、机构名等专有名词外，所有英文句子都必须翻译成中文。每个段落直接从文字开始，不要在段首添加空格或缩进。不要分析、解释、总结，也不要添加标题或多余说明，不要使用 Markdown 或 **粗体** 标记。严格保持原文段落结构和换行位置，不要合并段落，也不要额外拆分段落。\n\n{{text}}",
            followUp: "下面是 AI view 上下文：\n{{context}}\n\n用户继续追问：\n{{text}}",
            readingFollowUp: "用户没有选中文字，正在基于当前阅读区提问。请结合当前阅读内容和 AI view 最近上下文回答用户问题。只回答用户问题，不要自动翻译整段，不要自动总结，除非用户明确要求。\n\n【当前阅读内容】\n{{readingText}}\n\n【AI view 最近上下文】\n{{context}}\n\n【用户问题】\n{{question}}",
            documentAgent: "用户正在阅读《{{title}}》，并提出了下面的问题。请像文档阅读 Agent 一样回答。\n\n处理方式：\n- 先根据【问题】和你对《{{title}}》的已知阅读理解，形成一个初步答案方向\n- 再用提供的当前页、当前章节或附近页面、文档检索结果校正、补充和约束这个答案\n- 最终输出时，把初步理解、阅读上下文、检索内容整合成一个连贯答案，不要分开罗列内部步骤\n\n要求：\n- 优先以提供的文档检索结果、当前章节或附近页面、当前页内容作为可引用依据\n- 你可以使用自己对作品的常识帮助理解问题，但不能用它覆盖文档证据\n- 能定位出处时，在句末标注页码，例如（第 12 页）\n- 如果检索结果和当前页都不足以支持结论，要明确说明文档里没有找到足够依据，再给出谨慎判断\n- 只回答用户问题，不要自动总结全文\n- 不要编造文档中没有的细节\n- 不要输出“初步答案”“检索整理”等标题，直接给最终答案\n\n【问题】\n{{questionLine}}\n\n{{currentPageSection}}\n{{chapterSection}}\n{{searchResultsSection}}\n【AI view 最近上下文】\n{{context}}"
        ),
        en: PromptLanguageConfig(
            system: "You are an English reading and vocabulary assistant. Be concise and practical.",
            compactSystem: "You are an English reading and vocabulary assistant. Keep answers compact: no consecutive blank lines, no padded sections, and no long answer unless the user asks for detail.",
            word: "Explain this word: {{word}}\n\nContext from the article:\n{{context}}\n\nOutput requirement: do not repeat the word as a first-line title. Start directly with pronunciation.",
            sentence: "Explain this English passage:\n\n{{text}}",
            difficultSentence: "Analyze this difficult English sentence in compact Markdown. Do not use tables or consecutive blank lines.\nInclude these sections:\n## Sentence structure\n## Subject, verb, object, clauses, and modifiers\n## Layered translation\n## Common expressions\n## Why it is written this way\n\n[English]\n{{text}}",
            summary: "Summarize the current reading content:\n\nTitle: {{title}}\n\nText:\n{{text}}",
            translation: "Translate the following content into clear, natural English. Output only the translation. Do not analyze, explain, summarize, add a title, add extra notes, or use Markdown or **bold** markers. Strictly preserve the original paragraph structure and line breaks. Do not merge paragraphs or split them into extra paragraphs.\n\n{{text}}",
            followUp: "AI view context:\n{{context}}\n\nUser follow-up:\n{{text}}",
            readingFollowUp: "The user did not select text and is asking about the current reading area. Answer using the current reading text and the recent AI view context. Answer only the user question. Do not automatically translate or summarize the whole passage unless explicitly asked.\n\n[Current reading text]\n{{readingText}}\n\n[Recent AI view context]\n{{context}}\n\n[User question]\n{{question}}",
            documentAgent: "The user is reading {{title}} and asks the following question. Answer like a document-reading agent.\n\nProcess:\n- First form an initial answer direction from [Question] and your general reading understanding of {{title}}.\n- Then use any provided current-page text, current chapter or nearby pages, and document search results to correct, support, and constrain that answer.\n- In the final output, synthesize the initial understanding, reading context, and retrieved evidence into one coherent answer. Do not list your internal steps separately.\n\nRequirements:\n- Use provided document search results, current chapter or nearby pages, and current-page text as the primary citable evidence.\n- You may use general knowledge of the work to understand the question, but do not let it override document evidence.\n- Cite page numbers when the evidence supports it, for example (p. 12).\n- If the retrieved and current-page evidence is insufficient, say the document does not provide enough support, then give a cautious judgment.\n- Answer only the user question. Do not automatically summarize the whole document.\n- Do not invent details that are not in the document.\n- Do not output headings like \"Initial answer\" or \"Retrieved evidence\". Output only the final answer.\n\n[Question]\n{{questionLine}}\n\n{{currentPageSection}}\n{{chapterSection}}\n{{searchResultsSection}}\n[Recent AI view context]\n{{context}}"
        )
    )
}
