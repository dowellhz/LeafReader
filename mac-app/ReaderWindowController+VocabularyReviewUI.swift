import Cocoa

extension ReaderWindowController {
    func populateVocabularyReviewContainer(_ container: NSView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool, autoPlayNewCard: Bool = true) {
        for view in container.subviews {
            view.removeFromSuperview()
        }
        let visibleRecords = vocabularyReviewRecords(records)
        if (vocabularyReviewContextShown || vocabularyReviewAnswerShown),
           let key = vocabularyReviewCardKey,
           let preservedRecord = records.first(where: { vocabularyReviewKey(for: $0) == key }) {
            let selectedPosition = visibleRecords.firstIndex(where: { vocabularyReviewKey(for: $0) == key }).map { $0 + 1 } ?? min(vocabularyReviewIndex + 1, max(1, visibleRecords.count))
            prepareVocabularyReviewTiming(for: preservedRecord, autoPlay: autoPlayNewCard)
            updateVocabularySummaryWithProgress(position: selectedPosition, total: max(visibleRecords.count, selectedPosition))
            let card = vocabularyReviewCard(
                record: preservedRecord,
                position: selectedPosition,
                total: max(visibleRecords.count, selectedPosition),
                contextShown: vocabularyReviewContextShown,
                answerShown: vocabularyReviewAnswerShown,
                isDark: isDark
            )
            container.addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                card.topAnchor.constraint(equalTo: container.topAnchor),
                card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            return
        }
        guard !visibleRecords.isEmpty else {
            let empty = emptyVocabularyState(filter: filter, isDark: isDark)
            container.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return
        }
        vocabularyReviewIndex = min(max(0, vocabularyReviewIndex), visibleRecords.count - 1)
        let selectedRecord: VocabularyExportRecord
        let selectedPosition: Int
        if (vocabularyReviewContextShown || vocabularyReviewAnswerShown),
           let key = vocabularyReviewCardKey,
           let preservedIndex = visibleRecords.firstIndex(where: { vocabularyReviewKey(for: $0) == key }) {
            selectedRecord = visibleRecords[preservedIndex]
            selectedPosition = preservedIndex + 1
            vocabularyReviewIndex = preservedIndex
        } else {
            selectedRecord = visibleRecords[vocabularyReviewIndex]
            selectedPosition = vocabularyReviewIndex + 1
        }
        prepareVocabularyReviewTiming(for: selectedRecord, autoPlay: autoPlayNewCard)
        updateVocabularySummaryWithProgress(position: selectedPosition, total: visibleRecords.count)
        let card = vocabularyReviewCard(
            record: selectedRecord,
            position: selectedPosition,
            total: visibleRecords.count,
            contextShown: vocabularyReviewContextShown,
            answerShown: vocabularyReviewAnswerShown,
            isDark: isDark
        )
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    func vocabularyReviewCard(record: VocabularyExportRecord, position: Int, total: Int, contextShown: Bool, answerShown: Bool, isDark: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = (isDark ? NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1) : NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (isDark ? NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1) : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: record.word)
        wordLabel.font = AppFont.semibold(ofSize: 34)
        wordLabel.textColor = isDark ? NSColor(red: 0.92, green: 0.95, blue: 0.98, alpha: 1) : NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        wordLabel.maximumNumberOfLines = 2
        wordLabel.lineBreakMode = .byWordWrapping
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentArea = NSView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false

        let footerArea = NSView()
        footerArea.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(wordLabel)
        card.addSubview(contentArea)
        card.addSubview(footerArea)

        if let spokenWord = vocabularySpeakerWord(record.word) {
            let button = VocabularySpeakerButton(title: "", target: self, action: #selector(playVocabularyWord(_:)))
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = NSColor.systemBlue
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

        NSLayoutConstraint.activate([
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            wordLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -82),

            contentArea.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 20),
            contentArea.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            contentArea.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34),
            contentArea.bottomAnchor.constraint(equalTo: footerArea.topAnchor, constant: -14),

            footerArea.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 34),
            footerArea.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34),
            footerArea.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            footerArea.heightAnchor.constraint(equalToConstant: 44)
        ])

        if answerShown {
            let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
            let answerText = vocabularyAnswerBody(record.answer, word: record.word)
            let meaningfulContext = isMeaningfulVocabularyContext(contextText) ? contextText : ""
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
                fontSize: 14,
                textColor: isDark ? NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1) : NSColor(red: 0.22, green: 0.25, blue: 0.31, alpha: 1)
            )
            textView.textStorage?.setAttributedString(
                emphasizedVocabularyWord(in: answerAttributedText, word: record.word, boldFontSize: 14)
            )
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

            let nextButton = vocabularyReviewActionButton(title: AppText.localized("下一个", "Next"), action: #selector(nextVocabularyReviewCard(_:)), width: vocabularyReviewButtonWidth)
            let footerButtons: NSView
            if vocabularyReviewDidScoreCurrentCard, !vocabularyReviewUndoSRSByID.isEmpty {
                let undoButton = vocabularyReviewActionButton(title: AppText.localized("撤销", "Undo"), action: #selector(undoVocabularyReviewScore(_:)), width: vocabularyReviewButtonWidth)
                footerButtons = vocabularyReviewButtonRow([undoButton, nextButton])
            } else {
                footerButtons = nextButton
            }
            footerArea.addSubview(footerButtons)
            NSLayoutConstraint.activate([
                footerButtons.trailingAnchor.constraint(equalTo: footerArea.trailingAnchor),
                footerButtons.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor)
            ])
        } else if contextShown {
            let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaningfulContext = isMeaningfulVocabularyContext(contextText) ? contextText : AppText.localized("没有可用的原文句子。", "No source sentence available.")
            let contextColor = isDark ? NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1) : NSColor(red: 0.22, green: 0.25, blue: 0.31, alpha: 1)
            let contextLabel = NSTextField(labelWithAttributedString: vocabularyExampleAttributedString(meaningfulContext, word: record.word, fontSize: 17, textColor: contextColor))
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

            let rememberedButton = vocabularyReviewActionButton(title: AppText.localized("想起来了", "Remembered"), action: #selector(rememberedAfterContextVocabularyCard(_:)), width: vocabularyReviewButtonWidth)
            let forgotButton = vocabularyReviewActionButton(title: AppText.localized("没想起来", "Forgot"), action: #selector(showVocabularyAnswer(_:)), width: vocabularyReviewButtonWidth)
            let buttons = vocabularyReviewButtonRow([rememberedButton, forgotButton])
            footerArea.addSubview(buttons)
            NSLayoutConstraint.activate([
                buttons.trailingAnchor.constraint(equalTo: footerArea.trailingAnchor),
                buttons.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor)
            ])
        } else {
            let rememberedButton = vocabularyReviewActionButton(title: AppText.localized("认识", "Know"), action: #selector(rememberedVocabularyCard(_:)), width: vocabularyReviewButtonWidth)
            let forgotButton = vocabularyReviewActionButton(title: AppText.localized("不认识", "Do not know"), action: #selector(showVocabularyContext(_:)), width: vocabularyReviewButtonWidth)
            let buttons = vocabularyReviewButtonRow([rememberedButton, forgotButton])
            footerArea.addSubview(buttons)
            NSLayoutConstraint.activate([
                buttons.trailingAnchor.constraint(equalTo: footerArea.trailingAnchor),
                buttons.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor)
            ])
        }

        return card
    }

    func vocabularyReviewActionButton(title: String, action: Selector, width: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = AppFont.semibold(ofSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return button
    }

    func vocabularyReviewButtonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    func vocabularyExampleAttributedString(_ text: String, word: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 8
        let attributed = NSAttributedString(
                string: text,
                attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
        return emphasizedVocabularyWord(in: attributed, word: word, boldFontSize: fontSize)
    }

    func emphasizedVocabularyWord(in attributed: NSAttributedString, word: String, boldFontSize: CGFloat) -> NSAttributedString {
        let target = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let pattern = vocabularyWordEmphasisPattern(for: target)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return attributed
        }
        let fullRange = NSRange(location: 0, length: (mutable.string as NSString).length)
        regex.enumerateMatches(in: mutable.string, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound, range.length > 0 else { return }
            mutable.addAttribute(.font, value: AppFont.semibold(ofSize: boldFontSize + 1), range: range)
        }
        return mutable
    }

    func vocabularyWordEmphasisPattern(for word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        if word.range(of: #"^[A-Za-z][A-Za-z'’-]*$"#, options: .regularExpression) != nil {
            return #"(?<![A-Za-z])"# + escaped + #"(?![A-Za-z])"#
        }
        return escaped
    }

}
