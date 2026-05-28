import Cocoa

extension ReaderWindowController {
    func populateVocabularyReviewContainer(_ container: NSView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool, autoPlayNewCard: Bool = true) {
        for view in container.subviews {
            view.removeFromSuperview()
        }
        guard let selection = VocabularyReviewCardSelector.selection(records: records, session: vocabularyReviewSession) else {
            let empty = emptyVocabularyState(filter: filter, isDark: isDark)
            container.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return
        }
        let displayRecord = vocabularyRecordWithDictionaryMetadata(selection.record)
        prepareVocabularyReviewTiming(for: displayRecord, autoPlay: autoPlayNewCard)
        updateVocabularySummaryWithProgress(position: selection.position, total: selection.total)
        addVocabularyReviewCard(
            to: container,
            record: displayRecord,
            position: selection.position,
            total: selection.total,
            contextShown: vocabularyReviewSession.contextShown,
            answerShown: vocabularyReviewSession.answerShown,
            didScore: vocabularyReviewSession.didScoreCurrentCard,
            canUndoScore: !vocabularyReviewSession.undoSRSByID.isEmpty
        )
    }

    private func addVocabularyReviewCard(
        to container: NSView,
        record: VocabularyExportRecord,
        position: Int,
        total: Int,
        contextShown: Bool,
        answerShown: Bool,
        didScore: Bool,
        canUndoScore: Bool
    ) {
        let card = VocabularyReviewCardBuilder(owner: self).build(
            record: record,
            position: position,
            total: total,
            contextShown: contextShown,
            answerShown: answerShown,
            didScore: didScore,
            canUndoScore: canUndoScore
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
        popup.addItem(withTitle: AppText.localized("词频优先", "Frequency First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.frequencyFirst.rawValue
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(changeVocabularyReviewPriority(_:))
        popup.theme = ReaderTheme.selected
        loadVocabularyReviewPriorityPreference()
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
        saveVocabularyReviewPriorityPreference(priority)
        vocabularyReviewSession.resetForReviewMode()
        if priority == .frequencyFirst {
            backfillFrequencyForCurrentTrainerIfNeeded(autoPlayAfterCompletion: true)
            return
        }
        showVocabularyReviewMode(in: root, autoPlay: true)
    }

    func showVocabularyFrequencyLoading(in root: NSView) {
        guard let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) else { return }
        for view in reviewContainer.subviews {
            view.removeFromSuperview()
        }
        let label = NSTextField(labelWithString: AppText.localized("正在处理词频，请稍候…", "Processing word frequency..."))
        label.font = AppFont.semibold(ofSize: 16)
        label.textColor = vocabularySecondaryTextColor(for: ReaderTheme.selected)
        label.alignment = .center
        label.identifier = NSUserInterfaceItemIdentifier("vocabularyFrequencyLoadingLabel")
        label.translatesAutoresizingMaskIntoConstraints = false
        reviewContainer.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: reviewContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: reviewContainer.centerYAnchor)
        ])
    }

    func updateVocabularyFrequencyLoading(in root: NSView, word: String, current: Int, total: Int) {
        guard let label = findView(identifier: "vocabularyFrequencyLoadingLabel", in: root) as? NSTextField else { return }
        label.stringValue = AppText.localized(
            "正在处理词频 \(current) / \(total)：\(word)",
            "Processing frequency \(current) / \(total): \(word)"
        )
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
