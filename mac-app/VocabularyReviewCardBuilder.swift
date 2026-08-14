import Cocoa

final class VocabularyReviewCardBuilder {
    private unowned let owner: ReaderWindowController
    private let contentBuilder: VocabularyReviewCardContentBuilder
    private let footerBuilder: VocabularyReviewCardFooterBuilder

    init(owner: ReaderWindowController) {
        self.owner = owner
        self.contentBuilder = VocabularyReviewCardContentBuilder(owner: owner)
        self.footerBuilder = VocabularyReviewCardFooterBuilder(owner: owner)
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
            contentBuilder.addAnswerContent(for: record, in: contentArea, theme: theme)
            footerBuilder.addAnswerFooter(to: footerArea, didScore: didScore, canUndoScore: canUndoScore)
        } else if contextShown {
            contentBuilder.addContextContent(for: record, in: contentArea, theme: theme)
            footerBuilder.addContextFooter(to: footerArea)
        } else {
            footerBuilder.addPromptFooter(to: footerArea)
        }

        return card
    }

    private func ecdictTagLabel(for record: VocabularyExportRecord, theme: ReaderTheme) -> NSTextField? {
        guard let tags = VocabularyTagFormatter.displayText(for: record.dictionaryTags) else {
            return nil
        }
        let label = NSTextField(labelWithString: tags)
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
        button.setAccessibilityLabel(AppText.localized("播放单词发音", "Play word pronunciation"))
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
}
