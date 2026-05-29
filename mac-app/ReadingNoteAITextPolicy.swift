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
        let nsError = error as NSError
        if nsError.code == -10 {
            return AppText.localized("请先配置 API Key", "Configure API Key first")
        }
        if nsError.domain == NSURLErrorDomain {
            return AppText.localized("AI 请求失败，请检查网络", "AI request failed. Check the network.")
        }
        return AppText.localized("AI 请求失败", "AI request failed")
    }
}
