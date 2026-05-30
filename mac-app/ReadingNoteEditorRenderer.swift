import Cocoa

enum ReadingNoteEditorRenderer {
    static func renderMarkdown(_ markdown: String, theme: ReaderTheme) -> NSAttributedString {
        ReadingNoteDocumentCodec.editorProjection(
            from: ReadingNoteDocument(markdown: markdown),
            fontSize: ReadingNotePanelMetrics.editorFontSize,
            textColor: ReadingNoteTheme.primaryText(theme)
        )
    }

    static func paragraphTypingAttributes(theme: ReaderTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: ReadingNotePanelMetrics.editorFontSize),
            .foregroundColor: ReadingNoteTheme.primaryText(theme),
            .leafMarkdownBlock: MarkdownRenderer.Block.paragraph.rawValue
        ]
    }

    static func typingAttributes(for block: MarkdownRenderer.Block, theme: ReaderTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: block),
            .foregroundColor: ReadingNoteTheme.primaryText(theme),
            .leafMarkdownBlock: block.rawValue
        ]
    }

    static func font(for block: MarkdownRenderer.Block) -> NSFont {
        switch block {
        case .heading1:
            return NSFont.boldSystemFont(ofSize: ReadingNotePanelMetrics.editorHeading1FontSize)
        case .heading2:
            return NSFont.boldSystemFont(ofSize: ReadingNotePanelMetrics.editorHeading2FontSize)
        case .heading3, .heading4, .heading5, .heading6:
            return NSFont.boldSystemFont(ofSize: ReadingNotePanelMetrics.editorHeadingFontSize)
        default:
            return NSFont.systemFont(ofSize: ReadingNotePanelMetrics.editorFontSize)
        }
    }

    static func defaultEditorFont() -> NSFont {
        NSFont.systemFont(ofSize: ReadingNotePanelMetrics.editorFontSize)
    }
}
