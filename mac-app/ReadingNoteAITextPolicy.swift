import Foundation

enum ReadingNoteAITextPolicy {
    static let noteContextLimit = 2000

    static func markdownBody(from value: String) -> String {
        var lines = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix("```") else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        lines.removeFirst()
        if let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), last == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func documentContext(selectedText: String, noteMarkdown: String, isChinese: Bool) -> String {
        let note = ReaderAIContextPolicy.prefix(noteMarkdown, limit: noteContextLimit)
        if isChinese {
            return """
            【阅读笔记选中内容】
            \(selectedText)

            【当前阅读笔记】
            \(note)
            """
        }
        return """
        [Selected reading-note text]
        \(selectedText)

        [Current reading note]
        \(note)
        """
    }

    static func userFacingError(_ error: Error) -> String {
        AIRequestErrorText.message(for: error)
    }

    static func emptyOutputMessage() -> String {
        AppText.localized(
            "AI 没有返回内容。请重试，或换一个问题。",
            "AI returned no content. Try again, or ask a different question."
        )
    }
}
