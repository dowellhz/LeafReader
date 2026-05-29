import Cocoa

extension ReadingNotePanelController {
    func renderMarkdownIntoEditor(_ markdown: String) {
        let rendered = MarkdownRenderer.render(
            markdown,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        textView.textStorage?.setAttributedString(rendered)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: ReadingNoteTheme.primaryText(ReaderTheme.selected),
            .leafMarkdownBlock: MarkdownRenderer.Block.paragraph.rawValue
        ]
    }

    func renderPastedMarkdownIfNeeded(in insertedRange: NSRange) {
        let nsText = textView.string as NSString
        guard nsText.length > 0 else { return }
        let bounded = ReadingNoteTextReplacementPolicy.boundedRange(
            location: insertedRange.location,
            length: insertedRange.length,
            textLength: nsText.length
        )
        let paragraphRange = nsText.paragraphRange(for: bounded)
        let markdown = nsText.substring(with: paragraphRange)
        guard ReadingNoteMarkdownInputPolicy.shouldRenderPastedText(markdown) else { return }
        let rendered = MarkdownRenderer.render(
            markdown,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        replaceText(
            in: paragraphRange,
            with: rendered,
            selection: .adjustedOriginal(textView.selectedRange())
        )
        save()
        updateWordCount()
    }

    func markdownFromEditor() -> String {
        ReadingNoteMarkdownSerializer.markdown(from: textView.attributedString())
    }

    func renderCompletedMarkdownLineBeforeCursor() {
        let originalSelection = textView.selectedRange()
        guard let range = completedMarkdownLineRangeBeforeCursor() else {
            resetMarkdownTypingAttributes()
            return
        }
        let nsText = textView.string as NSString
        let rawLine = nsText.substring(with: range).trimmingCharacters(in: .newlines)
        guard ReadingNoteMarkdownInputPolicy.shouldRenderCompletedLine(rawLine) else {
            resetMarkdownTypingAttributes()
            return
        }
        let rendered = MarkdownRenderer.render(
            rawLine,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        replaceText(
            in: range,
            with: rendered,
            selection: .adjustedOriginal(originalSelection)
        )
        resetMarkdownTypingAttributes()
    }

    private func completedMarkdownLineRangeBeforeCursor() -> NSRange? {
        let nsText = textView.string as NSString
        let cursor = min(textView.selectedRange().location, nsText.length)
        guard cursor > 0 else { return nil }
        let previousLocation = max(0, cursor - 1)
        let previousCharacter = nsText.substring(with: NSRange(location: previousLocation, length: 1))
        let lineLocation = previousCharacter == "\n" ? max(0, previousLocation - 1) : previousLocation
        guard lineLocation < nsText.length else { return nil }
        return nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
    }

}
