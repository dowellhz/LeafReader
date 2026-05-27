import Cocoa

final class VocabularyReviewCardBuilder {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func build(
        record: VocabularyExportRecord,
        position: Int,
        total: Int,
        contextShown: Bool,
        answerShown: Bool,
        didScore: Bool,
        canUndoScore: Bool
    ) -> NSView {
        let theme = ReaderTheme.selected
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = owner.vocabularyCardBackgroundColor(for: theme).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = owner.vocabularyCardBorderColor(for: theme).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: record.word)
        wordLabel.font = AppFont.semibold(ofSize: 36)
        wordLabel.textColor = owner.vocabularyPrimaryTextColor(for: theme)
        wordLabel.maximumNumberOfLines = 2
        wordLabel.lineBreakMode = .byWordWrapping
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let tagLabel = ecdictTagLabel(for: record, theme: theme)
        let contentArea = NSView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false

        let footerArea = NSView()
        footerArea.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(wordLabel)
        if let tagLabel {
            card.addSubview(tagLabel)
        }
        card.addSubview(contentArea)
        card.addSubview(footerArea)

        addSpeakerButtonIfNeeded(for: record, wordLabel: wordLabel, card: card, theme: theme)
        constrainCard(card, wordLabel: wordLabel, tagLabel: tagLabel, contentArea: contentArea, footerArea: footerArea)

        if answerShown {
            addAnswerContent(for: record, in: contentArea, footerArea: footerArea, theme: theme, didScore: didScore, canUndoScore: canUndoScore)
        } else if contextShown {
            addContextContent(for: record, in: contentArea, footerArea: footerArea, theme: theme)
        } else {
            addPromptButtons(in: footerArea)
        }

        return card
    }

    private func ecdictTagLabel(for record: VocabularyExportRecord, theme: ReaderTheme) -> NSTextField? {
        guard let tags = record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tags.isEmpty else {
            return nil
        }
        let label = NSTextField(labelWithString: tags.uppercased())
        label.font = AppFont.semibold(ofSize: 15)
        label.textColor = owner.vocabularySecondaryTextColor(for: theme)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func addSpeakerButtonIfNeeded(
        for record: VocabularyExportRecord,
        wordLabel: NSTextField,
        card: NSView,
        theme: ReaderTheme
    ) {
        guard let spokenWord = owner.vocabularySpeakerWord(record.word) else { return }
        let button = VocabularySpeakerButton(title: "", target: owner, action: #selector(ReaderWindowController.playVocabularyWord(_:)))
        button.image = TemplateSymbolImage.make("speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
        button.isBordered = false
        button.contentTintColor = owner.vocabularyAccentColor(for: theme)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.spokenWord = spokenWord
        button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
        button.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: wordLabel.trailingAnchor, constant: 12),
            button.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func constrainCard(
        _ card: NSView,
        wordLabel: NSTextField,
        tagLabel: NSTextField?,
        contentArea: NSView,
        footerArea: NSView
    ) {
        var constraints: [NSLayoutConstraint] = [
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            wordLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -82),

            contentArea.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            contentArea.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34),
            contentArea.bottomAnchor.constraint(equalTo: footerArea.topAnchor, constant: -14),

            footerArea.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            footerArea.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34),
            footerArea.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            footerArea.heightAnchor.constraint(equalToConstant: 44)
        ]
        if let tagLabel {
            constraints.append(contentsOf: [
                tagLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 6),
                tagLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
                tagLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -34),
                contentArea.topAnchor.constraint(equalTo: tagLabel.bottomAnchor, constant: 16)
            ])
        } else {
            constraints.append(contentArea.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 20))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func addAnswerContent(
        for record: VocabularyExportRecord,
        in contentArea: NSView,
        footerArea: NSView,
        theme: ReaderTheme,
        didScore: Bool,
        canUndoScore: Bool
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

        let nextButton = reviewActionButton(title: AppText.localized("下一个", "Next"), action: #selector(ReaderWindowController.nextVocabularyReviewCard(_:)), isPrimary: true)
        let footerButtons: NSView
        if didScore, canUndoScore {
            let undoButton = reviewActionButton(title: AppText.localized("撤销", "Undo"), action: #selector(ReaderWindowController.undoVocabularyReviewScore(_:)))
            footerButtons = reviewButtonRow([undoButton, nextButton])
        } else {
            footerButtons = nextButton
        }
        addFooterButtons(footerButtons, to: footerArea)
    }

    private func addContextContent(
        for record: VocabularyExportRecord,
        in contentArea: NSView,
        footerArea: NSView,
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

        let rememberedButton = reviewActionButton(title: AppText.localized("想起来了", "Remembered"), action: #selector(ReaderWindowController.rememberedAfterContextVocabularyCard(_:)), isPrimary: true)
        let forgotButton = reviewActionButton(title: AppText.localized("没想起来", "Forgot"), action: #selector(ReaderWindowController.showVocabularyAnswer(_:)))
        addFooterButtons(reviewButtonRow([rememberedButton, forgotButton]), to: footerArea)
    }

    private func addPromptButtons(in footerArea: NSView) {
        let rememberedButton = reviewActionButton(title: AppText.localized("认识", "Know"), action: #selector(ReaderWindowController.rememberedVocabularyCard(_:)), isPrimary: true)
        let forgotButton = reviewActionButton(title: AppText.localized("不认识", "Do not know"), action: #selector(ReaderWindowController.showVocabularyContext(_:)))
        addFooterButtons(reviewButtonRow([rememberedButton, forgotButton]), to: footerArea)
    }

    private func addFooterButtons(_ buttons: NSView, to footerArea: NSView) {
        footerArea.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: footerArea.trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor)
        ])
    }

    private func reviewActionButton(title: String, action: Selector, isPrimary: Bool = false) -> NSButton {
        let button = owner.vocabularyActionButton(
            title: title,
            target: owner,
            action: action,
            fontSize: owner.vocabularyReviewButtonFontSize,
            isPrimary: isPrimary
        )
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: owner.vocabularyReviewButtonWidth),
            button.heightAnchor.constraint(equalToConstant: owner.vocabularyReviewButtonHeight)
        ])
        return button
    }

    private func reviewButtonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}
