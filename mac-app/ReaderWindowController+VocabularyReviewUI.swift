import Cocoa

extension ReaderWindowController {
    func populateVocabularyReviewContainer(_ container: NSView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool, autoPlayNewCard: Bool = true) {
        for view in container.subviews {
            view.removeFromSuperview()
        }
        let visibleRecords = vocabularyReviewRecords(records)
        if (vocabularyReviewSession.contextShown || vocabularyReviewSession.answerShown),
           let key = vocabularyReviewSession.cardKey,
           let preservedRecord = records.first(where: { vocabularyReviewSession.key(for: $0) == key }) {
            let selectedPosition = visibleRecords.firstIndex(where: { vocabularyReviewSession.key(for: $0) == key }).map { $0 + 1 } ?? min(vocabularyReviewSession.reviewIndex + 1, max(1, visibleRecords.count))
            prepareVocabularyReviewTiming(for: preservedRecord, autoPlay: autoPlayNewCard)
            updateVocabularySummaryWithProgress(position: selectedPosition, total: max(visibleRecords.count, selectedPosition))
            let card = VocabularyReviewCardBuilder(owner: self).build(
                record: preservedRecord,
                position: selectedPosition,
                total: max(visibleRecords.count, selectedPosition),
                contextShown: vocabularyReviewSession.contextShown,
                answerShown: vocabularyReviewSession.answerShown,
                didScore: vocabularyReviewSession.didScoreCurrentCard,
                canUndoScore: !vocabularyReviewSession.undoSRSByID.isEmpty
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
        vocabularyReviewSession.reviewIndex = min(max(0, vocabularyReviewSession.reviewIndex), visibleRecords.count - 1)
        let selectedRecord: VocabularyExportRecord
        let selectedPosition: Int
        if (vocabularyReviewSession.contextShown || vocabularyReviewSession.answerShown),
           let key = vocabularyReviewSession.cardKey,
           let preservedIndex = visibleRecords.firstIndex(where: { vocabularyReviewSession.key(for: $0) == key }) {
            selectedRecord = visibleRecords[preservedIndex]
            selectedPosition = preservedIndex + 1
            vocabularyReviewSession.reviewIndex = preservedIndex
        } else {
            selectedRecord = visibleRecords[vocabularyReviewSession.reviewIndex]
            selectedPosition = vocabularyReviewSession.reviewIndex + 1
        }
        prepareVocabularyReviewTiming(for: selectedRecord, autoPlay: autoPlayNewCard)
        updateVocabularySummaryWithProgress(position: selectedPosition, total: visibleRecords.count)
        let card = VocabularyReviewCardBuilder(owner: self).build(
            record: selectedRecord,
            position: selectedPosition,
            total: visibleRecords.count,
            contextShown: vocabularyReviewSession.contextShown,
            answerShown: vocabularyReviewSession.answerShown,
            didScore: vocabularyReviewSession.didScoreCurrentCard,
            canUndoScore: !vocabularyReviewSession.undoSRSByID.isEmpty
        )
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    func vocabularyReviewPriorityPopup() -> NSPopUpButton {
        let popup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: 13)
        popup.isBordered = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItem(withTitle: AppText.localized("老单词优先", "Old Words First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.oldWordsFirst.rawValue
        popup.addItem(withTitle: AppText.localized("新单词优先", "New Words First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.newWordsFirst.rawValue
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(changeVocabularyReviewPriority(_:))
        popup.theme = ReaderTheme.selected
        if let index = popup.itemArray.firstIndex(where: { item in
            (item.representedObject as? String) == vocabularyReviewSession.priority.rawValue
        }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    @objc func changeVocabularyReviewPriority(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let priority = VocabularyReviewPriority(rawValue: rawValue),
              priority != vocabularyReviewSession.priority,
              let root = vocabularyPanelController.rootView else { return }
        commitPendingVocabularyAnswerIfNeeded()
        vocabularyReviewSession.priority = priority
        vocabularyReviewSession.resetForReviewMode()
        showVocabularyReviewMode(in: root, autoPlay: true)
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
        VocabularyTextPolicy.emphasisPattern(for: word)
    }

}
