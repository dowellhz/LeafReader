import Cocoa

extension ReaderWindowController {
    func populateVocabularyReviewContainer(_ container: NSView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool, autoPlayNewCard: Bool = true) {
        VocabularyReviewCoordinator(owner: self).populate(
            container: container,
            records: records,
            filter: filter,
            isDark: isDark,
            autoPlayNewCard: autoPlayNewCard
        )
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
        loadVocabularyReviewPreferences()
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

    func vocabularyDailyGoalPopup() -> NSPopUpButton {
        let popup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: 13)
        popup.isBordered = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        for goal in VocabularyDailyGoalPolicy.options {
            popup.addItem(withTitle: AppText.localized("目标 \(goal)", "Goal \(goal)"))
            popup.lastItem?.representedObject = goal
        }
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(changeVocabularyDailyGoal(_:))
        popup.theme = ReaderTheme.selected
        loadVocabularyReviewPreferences()
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == vocabularyReviewSession.dailyReviewGoal }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    @objc func changeVocabularyDailyGoal(_ sender: NSPopUpButton) {
        guard let goal = sender.selectedItem?.representedObject as? Int,
              let root = vocabularyPanelController.rootView else { return }
        vocabularyReviewSession.dailyReviewGoal = goal
        saveVocabularyDailyGoalPreference(goal)
        if let summary = findView(identifier: "vocabularySummaryLabel", in: root) as? NSTextField {
            summary.stringValue = vocabularySummaryText(records: currentVocabularyExportRecords, filter: vocabularyReviewSession.filter)
        }
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
