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

    func runQuestion(question: String, selectedText: String, completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !trimmedSelection.isEmpty else {
            completion(.success(""))
            return
        }
        let messages = [
            ChatMessage(role: "system", content: AIPromptStore.systemPrompt()),
            ChatMessage(role: "user", content: questionPrompt(question: trimmedQuestion, selectedText: trimmedSelection))
        ]
        task = client.send(messages: messages) { [weak self] result in
            DispatchQueue.main.async {
                self?.task = nil
                completion(result)
            }
        }
    }

    func runPrompt(_ prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(""))
            return
        }
        let messages = [
            ChatMessage(role: "system", content: AIPromptStore.systemPrompt()),
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
                请润色下面这段阅读笔记文字，使表达更自然、清晰、流畅。
                要求：
                - 保留原意，不扩写事实。
                - 保持原文语言，不要翻译。英文仍输出英文，中文仍输出中文，中英混合时保留各自语言。
                - 不加标题，不解释修改过程，只输出润色后的文字。

                【原文】
                \(text)
                """
            }
            return """
            Polish the following reading-note text so it reads more naturally, clearly, and fluently.
            Preserve the original meaning and original language. Do not translate; English should remain English, Chinese should remain Chinese, and mixed-language text should keep each language as-is.
            Do not add facts, headings, or explanations.
            Output only the polished text.

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
