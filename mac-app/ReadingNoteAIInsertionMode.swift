import Foundation

enum ReadingNoteAIInsertionMode {
    case appendSection(title: String)
    case replacePlaceholder(title: String)
    case replaceSelection(
        NSRange,
        renderMarkdown: Bool,
        protectedMarkdown: ReadingNoteAIMarkdownImageProtector.ProtectedMarkdown? = nil
    )
    case replaceRange(
        NSRange,
        renderMarkdown: Bool,
        prefix: String = "",
        protectedMarkdown: ReadingNoteAIMarkdownImageProtector.ProtectedMarkdown? = nil
    )
    case replaceSlashTrigger

    var usesPlaceholder: Bool {
        if case .replacePlaceholder = self {
            return true
        }
        return false
    }
}
