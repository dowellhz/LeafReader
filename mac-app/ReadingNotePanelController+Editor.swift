import Cocoa

extension ReadingNotePanelController {
    func configureEditorTextView(in scrollView: NSScrollView) {
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.onSelectionChanged = { [weak self] in
            self?.refreshAIToolbar()
        }
        textView.onSlashCommand = { [weak self] in
            self?.showSlashCommandMenu()
        }
        textView.onCommitMarkdownLine = { [weak self] in
            self?.renderCompletedMarkdownLineBeforeCursor()
        }
        textView.onMarkdownPaste = { [weak self] insertedRange in
            self?.renderPastedMarkdownIfNeeded(in: insertedRange)
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 22, height: 22)
        scrollView.documentView = textView
    }
}
