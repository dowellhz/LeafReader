import Foundation

final class AITextActionRunner {
    enum Action {
        case explain
        case translate
        case summarize
        case polish
        case continueLine
    }

    private let client = AIClient()
    private var task: URLSessionDataTask?

    var isRunning: Bool {
        task != nil
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(action: Action, text: String, noteContext: String = "", completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(""))
            return
        }
        let messages = [
            ChatMessage(role: "system", content: AIPromptStore.systemPrompt()),
            ChatMessage(role: "user", content: prompt(action: action, text: trimmed, noteContext: noteContext))
        ]
        task = client.send(messages: messages) { [weak self] result in
            DispatchQueue.main.async {
                self?.task = nil
                completion(result)
            }
        }
    }

    func runQuestion(
        question: String,
        selectedText: String,
        systemPrompt: String = AIPromptStore.systemPrompt(),
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        cancel()
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !trimmedSelection.isEmpty else {
            completion(.success(""))
            return
        }
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: questionPrompt(question: trimmedQuestion, selectedText: trimmedSelection))
        ]
        task = client.send(messages: messages) { [weak self] result in
            DispatchQueue.main.async {
                self?.task = nil
                completion(result)
            }
        }
    }

    func runPrompt(
        _ prompt: String,
        systemPrompt: String = AIPromptStore.systemPrompt(),
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        cancel()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(""))
            return
        }
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: trimmed)
        ]
        task = client.send(messages: messages) { [weak self] result in
            DispatchQueue.main.async {
                self?.task = nil
                completion(result)
            }
        }
    }

    private func prompt(action: Action, text: String, noteContext: String) -> String {
        switch action {
        case .explain:
            return AIPromptStore.sentencePrompt(for: text)
        case .translate:
            return AIPromptStore.translationPrompt(title: text, text: text)
        case .summarize:
            return AIPromptStore.summaryPrompt(title: text, text: text)
        case .polish:
            if AppText.isChinese {
                return """
                请整理下面这段阅读笔记文字，输出结构清晰的 Markdown。
                要求：
                - 保留原意，不扩写事实，不添加原文没有的信息。
                - 保持原文语言，不要翻译。英文仍输出英文，中文仍输出中文，中英混合时保留各自语言。
                - 可以使用标题、列表、引用、粗体、任务列表等 Markdown 结构，让笔记更易读。
                - 不要包裹在代码块里，不解释整理过程，只输出 Markdown 正文。

                【原文】
                \(text)
                """
            }
            return """
            Organize the following reading-note text into clear Markdown.
            Preserve the original meaning, but output the organized note in English regardless of the source text language.
            Do not add facts that are not in the original text.
            You may use headings, bullet lists, blockquotes, bold text, and task lists to make the note easier to read.
            Do not wrap the output in a code block. Output only the Markdown body, with no explanation of your process.

            [Original text]
            \(text)
            """
        case .continueLine:
            if AppText.isChinese {
                return """
                你正在帮用户补充阅读笔记。请基于已有笔记和光标前内容，只补充一行简洁、有用的内容。
                要求：只输出这一行，不要解释，不要加标题。

                【已有笔记】
                \(noteContext)

                【光标前内容】
                \(text)
                """
            }
            return """
            Continue the user's reading note with exactly one concise, useful line.
            Output only that line. Do not explain or add a heading.

            [Existing note]
            \(noteContext)

            [Text before cursor]
            \(text)
            """
        }
    }

    private func questionPrompt(question: String, selectedText: String) -> String {
        if AppText.isChinese {
            return """
            请根据选中内容回答问题。
            要求：只回答问题本身；不要默认解释、翻译或总结选中内容，除非问题明确要求。

            【选中内容】
            \(selectedText)

            【问题】
            \(question)
            """
        }
        return """
        Answer the question based on the selected text.
        Requirement: answer only the question itself; do not default to explaining, translating, or summarizing the selected text unless explicitly asked.

        [Selected text]
        \(selectedText)

        [Question]
        \(question)
        """
    }
}
