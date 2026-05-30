import Cocoa

extension ReadingNotePanelController {
    func renderMarkdownIntoEditor(_ markdown: String) {
        renderDocumentIntoEditor(ReadingNoteDocument(markdown: markdown))
    }

    func renderDocumentIntoEditor(_ document: ReadingNoteDocument) {
        let rendered = ReadingNoteEditorRenderer.renderMarkdown(document.markdown, theme: ReaderTheme.selected)
        textView.textStorage?.setAttributedString(rendered)
        textView.typingAttributes = ReadingNoteEditorRenderer.paragraphTypingAttributes(theme: ReaderTheme.selected)
        refreshEditorDerivedState()
    }

    func renderPastedMarkdownIfNeeded(in insertedRange: NSRange) {
        guard let paragraphRange = ReadingNoteMarkdownRenderRangePolicy.pastedParagraphRange(
            text: textView.string,
            insertedRange: insertedRange
        ) else { return }
        let markdown = (textView.string as NSString).substring(with: paragraphRange)
        guard ReadingNoteMarkdownInputPolicy.shouldRenderPastedText(markdown) else { return }
        let rendered = ReadingNoteEditorRenderer.renderMarkdown(markdown, theme: ReaderTheme.selected)
        replaceText(
            in: paragraphRange,
            with: rendered,
            selection: .adjustedOriginal(textView.selectedRange())
        )
    }

    func markdownFromEditor() -> String {
        documentFromEditor().markdown
    }

    func documentFromEditor() -> ReadingNoteDocument {
        ReadingNoteDocumentCodec.document(fromEditorProjection: textView.attributedString())
    }

    func renderCompletedMarkdownLineBeforeCursor() {
        let originalSelection = textView.selectedRange()
        guard let range = ReadingNoteMarkdownRenderRangePolicy.completedLineRangeBeforeCursor(
            text: textView.string,
            selection: originalSelection
        ) else {
            resetMarkdownTypingAttributes()
            return
        }
        let nsText = textView.string as NSString
        let rawLine = nsText.substring(with: range).trimmingCharacters(in: .newlines)
        guard ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine(rawLine) else {
            resetMarkdownTypingAttributes()
            return
        }
        let rendered = ReadingNoteEditorRenderer.renderMarkdown(rawLine, theme: ReaderTheme.selected)
        replaceText(
            in: range,
            with: rendered,
            selection: .adjustedOriginal(originalSelection)
        )
        resetMarkdownTypingAttributes()
    }

}
