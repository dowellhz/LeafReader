import Foundation

enum ReadingNoteTemplate: String, CaseIterable {
    case reading
    case phrase
    case character

    var title: String {
        switch self {
        case .reading:
            return AppText.localized("阅读理解模板", "Reading template")
        case .phrase:
            return AppText.localized("短语/句子模板", "Phrase template")
        case .character:
            return AppText.localized("人物/事件模板", "Character/event template")
        }
    }

    var insertionStatus: String {
        switch self {
        case .reading:
            return AppText.localized("已插入阅读模板", "Reading template inserted")
        case .phrase:
            return AppText.localized("已插入短语模板", "Phrase template inserted")
        case .character:
            return AppText.localized("已插入人物/事件模板", "Character/event template inserted")
        }
    }

    func markdown(quote: String) -> String {
        switch self {
        case .reading:
            return [
                quoteSection(quote),
                heading(AppText.localized("翻译", "Translation")),
                "",
                heading(AppText.localized("核心思想", "Core Idea")),
                "",
                "- ",
                "",
                heading(AppText.localized("解析", "Analysis")),
                "",
                "- ",
                "",
                heading(AppText.localized("疑问", "Questions")),
                "",
                "- "
            ].joined(separator: "\n")
        case .phrase:
            return [
                quoteSection(quote),
                heading(AppText.localized("翻译", "Translation")),
                "",
                heading(AppText.localized("用法", "Usage")),
                "",
                "- ",
                "",
                heading(AppText.localized("例句", "Examples")),
                "",
                "1. ",
                "",
                heading(AppText.localized("记忆点", "Memory Notes")),
                "",
                "- "
            ].joined(separator: "\n")
        case .character:
            return [
                quoteSection(quote),
                heading(AppText.localized("人物 / 事件", "Character / Event")),
                "",
                "- ",
                "",
                heading(AppText.localized("关系与动机", "Relationship And Motivation")),
                "",
                "- ",
                "",
                heading(AppText.localized("情节作用", "Plot Function")),
                "",
                "- ",
                "",
                heading(AppText.localized("伏笔 / 疑问", "Foreshadowing / Questions")),
                "",
                "- "
            ].joined(separator: "\n")
        }
    }

    private func quoteSection(_ quote: String) -> String {
        let body = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = heading(AppText.localized("原文", "Original"))
        guard !body.isEmpty else { return "\(title)\n\n" }
        return "\(title)\n\n\(ReadingNoteMarkdown.blockquote(body))\n"
    }

    private func heading(_ title: String) -> String {
        "## \(title)"
    }
}

enum ReadingNoteTemplateInsertionPolicy {
    static func shouldReplaceExistingMarkdown(currentMarkdown: String, defaultMarkdown: String) -> Bool {
        let current = currentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return true }
        return current == defaultMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func spacerBeforeInsertion(existingText: String) -> String {
        guard !existingText.isEmpty else { return "" }
        if existingText.hasSuffix("\n\n") { return "" }
        return existingText.hasSuffix("\n") ? "\n" : "\n\n"
    }
}
