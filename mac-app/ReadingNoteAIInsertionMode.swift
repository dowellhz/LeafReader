import Foundation

enum ReadingNoteAIInsertionMode {
    case appendSection(title: String)
    case replacePlaceholder(title: String)
    case replaceSelection(NSRange, renderMarkdown: Bool)
    case replaceSlashTrigger

    var usesPlaceholder: Bool {
        if case .replacePlaceholder = self {
            return true
        }
        return false
    }
}
