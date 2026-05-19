import Cocoa

extension ReaderWindowController {
    func vocabularyCard(record: VocabularyExportRecord, isDark: Bool) -> NSView {
        let word = record.word
        let answer = record.answer
        let location = record.location
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = (isDark ? NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1) : NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (isDark ? NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1) : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let bullet = NSTextField(labelWithString: "•")
        bullet.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        bullet.textColor = NSColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 1)
        bullet.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: word)
        wordLabel.font = AppFont.semibold(ofSize: 17)
        wordLabel.textColor = isDark ? NSColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1) : NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let speakerButton: VocabularySpeakerButton? = vocabularySpeakerWord(word).map { spokenWord in
            let button = VocabularySpeakerButton(title: "", target: self, action: #selector(playVocabularyWord(_:)))
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = NSColor.systemBlue
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.spokenWord = spokenWord
            button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }

        let locationLabel = NSTextField(labelWithString: location)
        locationLabel.font = AppFont.semibold(ofSize: 12)
        locationLabel.textColor = isDark ? NSColor(red: 0.56, green: 0.63, blue: 0.72, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        locationLabel.alignment = .right
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let srsLabel = NSTextField(labelWithString: vocabularySRSStatusText(record.srs))
        srsLabel.font = AppFont.semibold(ofSize: 12)
        srsLabel.textColor = isDark ? NSColor(red: 0.58, green: 0.67, blue: 0.78, alpha: 1) : NSColor(red: 0.40, green: 0.48, blue: 0.62, alpha: 1)
        srsLabel.lineBreakMode = .byTruncatingTail
        srsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        srsLabel.translatesAutoresizingMaskIntoConstraints = false

        let masteredButton = NSButton(title: AppText.localized("删除", "Delete"), target: self, action: #selector(markVocabularyRecordMastered(_:)))
        masteredButton.bezelStyle = .rounded
        masteredButton.controlSize = .small
        masteredButton.font = AppFont.semibold(ofSize: 12)
        masteredButton.identifier = NSUserInterfaceItemIdentifier(record.ids.joined(separator: "|"))
        masteredButton.translatesAutoresizingMaskIntoConstraints = false

        let answerColor = isDark ? NSColor(red: 0.76, green: 0.80, blue: 0.86, alpha: 1) : NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1)
        let answerBody = vocabularyAnswerBody(answer, word: word)
        let answerLabel = NSTextField(labelWithAttributedString: MarkdownRenderer.render(String(answerBody.prefix(900)), fontSize: 13, textColor: answerColor))
        answerLabel.maximumNumberOfLines = 0
        answerLabel.lineBreakMode = .byWordWrapping
        answerLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [bullet, wordLabel, locationLabel, srsLabel, answerLabel] {
            card.addSubview(view)
        }
        if let speakerButton {
            card.addSubview(speakerButton)
        }
        card.addSubview(masteredButton)

        NSLayoutConstraint.activate([
            bullet.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            bullet.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            wordLabel.leadingAnchor.constraint(equalTo: bullet.trailingAnchor, constant: 8),
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            locationLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            locationLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            srsLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            srsLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 6),
            srsLabel.trailingAnchor.constraint(lessThanOrEqualTo: masteredButton.leadingAnchor, constant: -12),
            masteredButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            masteredButton.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 6),
            masteredButton.widthAnchor.constraint(equalToConstant: 72),
            masteredButton.heightAnchor.constraint(equalToConstant: 26),
            answerLabel.topAnchor.constraint(equalTo: srsLabel.bottomAnchor, constant: 12),
            answerLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            answerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            answerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
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
