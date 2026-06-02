import Foundation

enum ReadingNoteSlashCommand: String, CaseIterable {
    case text
    case heading1
    case heading2
    case heading3
    case heading4
    case bulletedList
    case numberedList
    case template
    case aiContinue
    case aiExplain
    case aiTranslate
    case aiSummarize
    case aiOrganize

    var title: String {
        switch self {
        case .text: return AppText.localized("文本", "Text")
        case .heading1: return AppText.localized("标题 1", "Heading 1")
        case .heading2: return AppText.localized("标题 2", "Heading 2")
        case .heading3: return AppText.localized("标题 3", "Heading 3")
        case .heading4: return AppText.localized("标题 4", "Heading 4")
        case .bulletedList: return AppText.localized("项目列表", "Bulleted list")
        case .numberedList: return AppText.localized("编号列表", "Numbered list")
        case .template: return AppText.localized("阅读笔记模板", "Reading note template")
        case .aiContinue: return AppText.localized("AI 补全", "AI complete")
        case .aiExplain: return AppText.localized("AI 解析选中内容", "AI explain selection")
        case .aiTranslate: return AppText.localized("AI 翻译选中内容", "AI translate selection")
        case .aiSummarize: return AppText.localized("AI 总结选中内容", "AI summarize selection")
        case .aiOrganize: return AppText.localized("AI 整理选中内容", "AI organize selection")
        }
    }

    var marker: String {
        switch self {
        case .text: return ""
        case .heading1: return "# "
        case .heading2: return "## "
        case .heading3: return "### "
        case .heading4: return "#### "
        case .bulletedList: return "- "
        case .numberedList: return "1. "
        case .template: return "模板"
        case .aiContinue: return "AI"
        case .aiExplain: return "AI"
        case .aiTranslate: return "AI"
        case .aiSummarize: return "AI"
        case .aiOrganize: return "AI"
        }
    }

    var isAICommand: Bool {
        switch self {
        case .aiContinue, .aiExplain, .aiTranslate, .aiSummarize, .aiOrganize:
            return true
        case .text, .heading1, .heading2, .heading3, .heading4, .bulletedList, .numberedList, .template:
            return false
        }
    }

    static var blockCommands: [ReadingNoteSlashCommand] {
        [.text, .heading1, .heading2, .heading3, .heading4, .bulletedList, .numberedList, .template]
    }

    static var aiCommands: [ReadingNoteSlashCommand] {
        [.aiContinue]
    }
}
