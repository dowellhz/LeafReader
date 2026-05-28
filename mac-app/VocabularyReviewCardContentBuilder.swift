import Cocoa

final class VocabularyReviewCardContentBuilder {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func addAnswerContent(
        for record: VocabularyExportRecord,
        in contentArea: NSView,
        theme: ReaderTheme
    ) {
        let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
        let answerText = owner.vocabularyAnswerBody(record.answer, word: record.word)
        let meaningfulContext = owner.isMeaningfulVocabularyContext(contextText) ? contextText : ""
        let body = [
            meaningfulContext.isEmpty ? "" : AppText.localized("原文上下文：\(meaningfulContext)", "Context: \(meaningfulContext)"),
            answerText
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        let scrollView = VocabularyDetailScrollView()
        scrollView.contentView = VocabularyDetailClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: max(1, contentArea.bounds.width), height: 600))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: max(1, contentArea.bounds.width), height: CGFloat.greatestFiniteMagnitude)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let answerAttributedText = MarkdownRenderer.render(
            body,
            fontSize: 16,
            textColor: owner.vocabularyBodyTextColor(for: theme)
        )
        textView.textStorage?.setAttributedString(
            owner.emphasizedVocabularyWord(in: answerAttributedText, word: record.word, boldFontSize: 16)
        )
        textView.selectedTextAttributes = [
            .backgroundColor: owner.vocabularySelectionBackgroundColor(for: theme),
            .foregroundColor: owner.vocabularyBodyTextColor(for: theme)
        ]
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            textView.frame.size.height = max(280, ceil(layoutManager.usedRect(for: textContainer).height) + 16)
        }
        scrollView.documentView = textView
        contentArea.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            textView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    func addContextContent(
        for record: VocabularyExportRecord,
        in contentArea: NSView,
        theme: ReaderTheme
    ) {
        let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningfulContext = owner.isMeaningfulVocabularyContext(contextText) ? contextText : AppText.localized("没有可用的原文句子。", "No source sentence available.")
        let contextLabel = NSTextField(
            labelWithAttributedString: owner.vocabularyExampleAttributedString(
                meaningfulContext,
                word: record.word,
                fontSize: 19,
                textColor: owner.vocabularyBodyTextColor(for: theme)
            )
        )
        contextLabel.maximumNumberOfLines = 0
        contextLabel.lineBreakMode = .byWordWrapping
        contextLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contextLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(contextLabel)
        NSLayoutConstraint.activate([
            contextLabel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            contextLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            contextLabel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            contextLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentArea.bottomAnchor)
        ])
    }
}
