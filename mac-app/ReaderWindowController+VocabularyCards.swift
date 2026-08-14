import Cocoa

extension ReaderWindowController {
    func vocabularyCard(record: VocabularyExportRecord, isDark: Bool) -> NSView {
        let theme = ReaderTheme.selected
        let word = record.word
        let answer = record.answer
        let location = record.location
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = vocabularyCardBackgroundColor(for: theme).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = vocabularyCardBorderColor(for: theme).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let bullet = NSTextField(labelWithString: "•")
        bullet.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        bullet.textColor = vocabularyAccentColor(for: theme)
        bullet.alignment = .center
        bullet.translatesAutoresizingMaskIntoConstraints = false

        let titleLeadingGuide = NSLayoutGuide()
        card.addLayoutGuide(titleLeadingGuide)

        let wordLabel = NSTextField(labelWithString: word)
        wordLabel.font = AppFont.semibold(ofSize: 19)
        wordLabel.textColor = vocabularyPrimaryTextColor(for: theme)
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let speakerButton: VocabularySpeakerButton? = vocabularySpeakerWord(word).map { spokenWord in
            let button = VocabularySpeakerButton(title: "", target: self, action: #selector(playVocabularyWord(_:)))
            button.image = TemplateSymbolImage.make("speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = vocabularyAccentColor(for: theme)
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(AppText.localized("播放单词发音", "Play word pronunciation"))
            button.spokenWord = spokenWord
            button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }

        let locationLabel = NSTextField(labelWithString: location)
        locationLabel.font = AppFont.semibold(ofSize: 14)
        locationLabel.textColor = vocabularySecondaryTextColor(for: theme)
        locationLabel.alignment = .right
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let srsLabel = NSTextField(labelWithString: vocabularySRSStatusText(record.srs))
        srsLabel.font = AppFont.semibold(ofSize: 14)
        srsLabel.textColor = vocabularySecondaryTextColor(for: theme)
        srsLabel.lineBreakMode = .byTruncatingTail
        srsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        srsLabel.translatesAutoresizingMaskIntoConstraints = false

        let relatedForms = record.surfaceForms.filter {
            $0.caseInsensitiveCompare(word) != .orderedSame
        }
        let formsLabel: NSTextField? = relatedForms.isEmpty ? nil : {
            let text = AppText.localized(
                "词元：\(record.lemma) · 相关词形：\(relatedForms.joined(separator: "、"))",
                "Lemma: \(record.lemma) · Related forms: \(relatedForms.joined(separator: ", "))"
            )
            let label = NSTextField(labelWithString: text)
            label.font = AppFont.semibold(ofSize: 12)
            label.textColor = vocabularySecondaryTextColor(for: theme)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        let masteredButton = vocabularyActionButton(title: AppText.localized("删除", "Delete"), target: self, action: #selector(markVocabularyRecordMastered(_:)), fontSize: 14)
        masteredButton.controlSize = .small
        masteredButton.identifier = NSUserInterfaceItemIdentifier(record.ids.joined(separator: "|"))

        let definitionButton = vocabularyActionButton(
            title: AppText.localized("查看释义", "Definition"),
            target: self,
            action: #selector(showVocabularyDefinitionFromList(_:)),
            fontSize: 13
        )
        definitionButton.controlSize = .small
        definitionButton.identifier = record.ids.first.map { NSUserInterfaceItemIdentifier($0) }
        definitionButton.toolTip = AppText.localized("在阅读侧栏中查看完整释义", "Show the full definition in the reader sidebar")

        let answerColor = vocabularyBodyTextColor(for: theme)
        let answerBody = vocabularyAnswerBody(answer, word: word)
        let answerLabel = NSTextField(labelWithAttributedString: MarkdownRenderer.render(String(answerBody.prefix(900)), fontSize: 15, textColor: answerColor))
        answerLabel.maximumNumberOfLines = 0
        answerLabel.lineBreakMode = .byWordWrapping
        answerLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [bullet, wordLabel, locationLabel, srsLabel, answerLabel] {
            card.addSubview(view)
        }
        if let speakerButton {
            card.addSubview(speakerButton)
        }
        if let formsLabel {
            card.addSubview(formsLabel)
        }
        card.addSubview(definitionButton)
        card.addSubview(masteredButton)

        let answerTopAnchor = formsLabel?.bottomAnchor ?? srsLabel.bottomAnchor

        NSLayoutConstraint.activate([
            titleLeadingGuide.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 74),
            titleLeadingGuide.widthAnchor.constraint(equalToConstant: 0),
            bullet.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            bullet.centerXAnchor.constraint(equalTo: card.leadingAnchor, constant: 46),
            bullet.widthAnchor.constraint(equalToConstant: 18),
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            wordLabel.leadingAnchor.constraint(equalTo: titleLeadingGuide.leadingAnchor),
            locationLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            locationLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            srsLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            srsLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 6),
            srsLabel.trailingAnchor.constraint(lessThanOrEqualTo: definitionButton.leadingAnchor, constant: -12),
            masteredButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            masteredButton.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 6),
            masteredButton.widthAnchor.constraint(equalToConstant: 72),
            masteredButton.heightAnchor.constraint(equalToConstant: 26),
            definitionButton.trailingAnchor.constraint(equalTo: masteredButton.leadingAnchor, constant: -8),
            definitionButton.topAnchor.constraint(equalTo: masteredButton.topAnchor),
            definitionButton.widthAnchor.constraint(equalToConstant: 88),
            definitionButton.heightAnchor.constraint(equalToConstant: 26),
            answerLabel.topAnchor.constraint(equalTo: answerTopAnchor, constant: 12),
            answerLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            answerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            answerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        if let formsLabel {
            NSLayoutConstraint.activate([
                formsLabel.leadingAnchor.constraint(equalTo: srsLabel.leadingAnchor),
                formsLabel.topAnchor.constraint(equalTo: srsLabel.bottomAnchor, constant: 5),
                formsLabel.trailingAnchor.constraint(lessThanOrEqualTo: definitionButton.leadingAnchor, constant: -12)
            ])
        }
        if let speakerButton {
            NSLayoutConstraint.activate([
                speakerButton.leadingAnchor.constraint(equalTo: wordLabel.trailingAnchor, constant: 6),
                speakerButton.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
                speakerButton.widthAnchor.constraint(equalToConstant: 24),
                speakerButton.heightAnchor.constraint(equalToConstant: 24),
                speakerButton.trailingAnchor.constraint(lessThanOrEqualTo: locationLabel.leadingAnchor, constant: -12)
            ])
        } else {
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: locationLabel.leadingAnchor, constant: -12).isActive = true
        }
        return card
    }

    func vocabularySRSStatusText(_ srs: VocabularySRSState) -> String {
        let ef = String(format: "%.2f", srs.easeFactor)
        if srs.isMastered {
            return AppText.localized("已掌握 · 连续主动想起 \(srs.activeRecallStreak ?? 0) 次 · EF \(ef)", "Mastered · active recall streak \(srs.activeRecallStreak ?? 0) · EF \(ef)")
        }
        if srs.lapseCount >= 2 {
            return AppText.localized("吃力词 · 已查看答案 \(srs.lapseCount) 次 · EF \(ef)", "Hard word · answer checked \(srs.lapseCount)x · EF \(ef)")
        }
        if srs.isNew {
            return AppText.localized("新词 · 今天开始学习 · EF \(ef)", "New · start today · EF \(ef)")
        }
        if srs.isDue {
            return AppText.localized("今天复习 · 连续 \(srs.repetition) 次 · EF \(ef)", "Due today · streak \(srs.repetition) · EF \(ef)")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = srs.intervalDays == 0 ? .short : .none
        return AppText.localized(
            srs.intervalDays == 0 ? "下次：\(formatter.string(from: srs.dueDate)) · 短间隔重测 · EF \(ef)" : "下次：\(formatter.string(from: srs.dueDate)) · 间隔 \(srs.intervalDays) 天 · EF \(ef)",
            srs.intervalDays == 0 ? "Next: \(formatter.string(from: srs.dueDate)) · short retry · EF \(ef)" : "Next: \(formatter.string(from: srs.dueDate)) · \(srs.intervalDays)d · EF \(ef)"
        )
    }

    func isMeaningfulVocabularyContext(_ context: String) -> Bool {
        let contextText = VocabularyExporter.trimmed(context)
        guard contextText.count >= 3 else { return false }
        return contextText.range(of: #"[A-Za-z0-9\u{4e00}-\u{9fff}]"#, options: .regularExpression) != nil
    }
}
