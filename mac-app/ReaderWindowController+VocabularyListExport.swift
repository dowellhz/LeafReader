import Cocoa

extension ReaderWindowController {
    func populateVocabularyStack(_ stack: NSStackView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let visibleRecords = vocabularyRecords(records, matching: filter)
        if visibleRecords.isEmpty {
            stack.addArrangedSubview(emptyVocabularyState(filter: filter, isDark: isDark))
            return
        }
        let pageCount = vocabularyListPageCount(total: visibleRecords.count)
        vocabularyListPageIndex = min(max(0, vocabularyListPageIndex), pageCount - 1)
        let start = vocabularyListPageIndex * vocabularyListPageSize
        let end = min(start + vocabularyListPageSize, visibleRecords.count)
        for record in visibleRecords[start..<end] {
            stack.addArrangedSubview(vocabularyCard(record: record, isDark: isDark))
        }
        if pageCount > 1 {
            stack.addArrangedSubview(vocabularyPaginationView(currentPage: vocabularyListPageIndex, pageCount: pageCount, total: visibleRecords.count, isDark: isDark))
        }
    }

    func vocabularyListPageCount(total: Int) -> Int {
        max(1, Int(ceil(Double(total) / Double(vocabularyListPageSize))))
    }

    func vocabularyPaginationView(currentPage: Int, pageCount: Int, total: Int, isDark: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let previousButton = NSButton(title: AppText.localized("上一页", "Previous"), target: self, action: #selector(previousVocabularyListPage(_:)))
        previousButton.bezelStyle = .rounded
        previousButton.controlSize = .large
        previousButton.font = AppFont.semibold(ofSize: 13)
        previousButton.isEnabled = currentPage > 0
        previousButton.translatesAutoresizingMaskIntoConstraints = false

        let nextButton = NSButton(title: AppText.localized("下一页", "Next"), target: self, action: #selector(nextVocabularyListPage(_:)))
        nextButton.bezelStyle = .rounded
        nextButton.controlSize = .large
        nextButton.font = AppFont.semibold(ofSize: 13)
        nextButton.isEnabled = currentPage + 1 < pageCount
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        let pageLabel = NSTextField(labelWithString: AppText.localized("第 \(currentPage + 1) / \(pageCount) 页 · 共 \(total) 个", "Page \(currentPage + 1) / \(pageCount) · \(total) total"))
        pageLabel.font = AppFont.semibold(ofSize: 13)
        pageLabel.textColor = isDark ? NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [previousButton, pageLabel, nextButton] {
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            previousButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: pageLabel.leadingAnchor, constant: -14),
            previousButton.widthAnchor.constraint(equalToConstant: 86),
            previousButton.heightAnchor.constraint(equalToConstant: 32),
            pageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            nextButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 14),
            nextButton.widthAnchor.constraint(equalToConstant: 86),
            nextButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        return container
    }

    @objc func previousVocabularyListPage(_ sender: NSButton) {
        guard vocabularyListPageIndex > 0 else { return }
        vocabularyListPageIndex -= 1
        reloadVocabularyPanelContent()
    }

    @objc func nextVocabularyListPage(_ sender: NSButton) {
        vocabularyListPageIndex += 1
        reloadVocabularyPanelContent()
    }

    func vocabularyRecords(_ records: [VocabularyExportRecord], matching filter: VocabularyFilter) -> [VocabularyExportRecord] {
        switch filter {
        case .due:
            return records
                .filter { record in
                    guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
                    return Calendar.current.isDateInToday(lastReviewedAt)
                }
                .sorted {
                    ($0.srs.lastReviewedAt ?? $0.createdAt) > ($1.srs.lastReviewedAt ?? $1.createdAt)
                }
        case .new:
            return records
                .filter { Calendar.current.isDateInToday($0.createdAt) }
                .sorted { $0.createdAt > $1.createdAt }
        case .all:
            return records.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func vocabularyReviewRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        let batchKeys = ensureVocabularyReviewBatch(records: records)
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[vocabularyReviewKey(for: record)] = record
        }
        return batchKeys.compactMap { key in
            guard let record = recordsByKey[key] else { return nil }
            if vocabularyReviewIsShowingCurrentCard(key: key) {
                return record
            }
            guard !vocabularyRecordIsDoneForToday(record) else { return nil }
            return record
        }
    }

    @discardableResult
    func ensureVocabularyReviewBatch(records: [VocabularyExportRecord]) -> [String] {
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[vocabularyReviewKey(for: record)] = record
        }
        let remainingCurrentBatch = vocabularyReviewBatchKeys.filter { key in
            guard let record = recordsByKey[key] else { return false }
            if vocabularyReviewIsShowingCurrentCard(key: key) {
                return true
            }
            return !vocabularyRecordIsDoneForToday(record)
        }
        if !remainingCurrentBatch.isEmpty {
            vocabularyReviewBatchKeys = remainingCurrentBatch
            return remainingCurrentBatch
        }

        let nextBatch = vocabularyReviewQueue(records)
            .filter { !vocabularyRecordIsDoneForToday($0) }
            .prefix(10)
            .map { vocabularyReviewKey(for: $0) }
        vocabularyReviewBatchKeys = Array(nextBatch)
        return vocabularyReviewBatchKeys
    }

    func vocabularyReviewQueue(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        let dueRecords = records
            .filter { $0.srs.isDue }
            .sorted {
                if $0.srs.isNew != $1.srs.isNew {
                    return !$0.srs.isNew
                }
                return $0.srs.dueDate < $1.srs.dueDate
            }
        if !dueRecords.isEmpty {
            return dueRecords
        }
        return records
            .filter { !$0.srs.isMastered }
            .sorted { $0.srs.dueDate < $1.srs.dueDate }
    }

    func vocabularyRecordIsDoneForToday(_ record: VocabularyExportRecord) -> Bool {
        guard let lastReviewedAt = record.srs.lastReviewedAt,
              Calendar.current.isDateInToday(lastReviewedAt) else { return false }
        return (record.srs.activeRecallStreak ?? 0) > 0 && record.srs.intervalDays >= 1 && !record.srs.isDue
    }

    func vocabularyReviewIsShowingCurrentCard(key: String) -> Bool {
        (vocabularyReviewContextShown || vocabularyReviewAnswerShown) && vocabularyReviewCardKey == key
    }

    func vocabularySummaryText(records: [VocabularyExportRecord], filter: VocabularyFilter) -> String {
        let count = vocabularyRecords(records, matching: filter).count
        switch filter {
        case .due:
            return AppText.localized("今日复习 \(count) 个单词", "\(count) reviewed today")
        case .new:
            return AppText.localized("今日新词 \(count) 个单词", "\(count) new today")
        case .all:
            return AppText.localized("本书全部 \(count) 个单词", "\(count) total words")
        }
    }

    func updateVocabularySummaryWithProgress(position: Int, total: Int) {
        guard let root = vocabularyPanel?.contentView,
              let summary = findView(identifier: "vocabularySummaryLabel", in: root) as? NSTextField else { return }
        summary.stringValue = "\(vocabularySummaryText(records: currentVocabularyExportRecords, filter: vocabularyReviewFilter)) · \(position) / \(total)"
    }

    func emptyVocabularyState(filter: VocabularyFilter, isDark: Bool) -> NSView {
        let label = NSTextField(labelWithString: {
            switch filter {
            case .due:
                return AppText.localized("今天还没有学习过的单词", "No words studied today")
            case .new:
                return AppText.localized("今天没有新加入的单词", "No new words added today")
            case .all:
                return AppText.localized("暂无单词", "No words yet")
            }
        }())
        label.font = AppFont.semibold(ofSize: 15)
        label.textColor = isDark ? NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 120),
            label.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        return wrapper
    }

    func findView(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    @objc func closeVocabularyBook(_ sender: NSButton) {
        guard sender.identifier?.rawValue == "closeVocabularyBook",
              let panel = sender.window else { return }
        closeVocabularyPanel(panel)
    }

    func closeVocabularyPanel(_ panel: NSWindow) {
        commitPendingVocabularyAnswerIfNeeded()
        removeVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: window)
        vocabularyPanel = nil
    }

    func installVocabularyPanelActivationObserver() {
        removeVocabularyPanelActivationObserver()
        vocabularyPanelActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let panel = self?.vocabularyPanel else { return }
            ModalOverlayManager.shared.reactivate(panel)
        }
    }

    func removeVocabularyPanelActivationObserver() {
        if let vocabularyPanelActivationObserver {
            NotificationCenter.default.removeObserver(vocabularyPanelActivationObserver)
            self.vocabularyPanelActivationObserver = nil
        }
    }

    @objc func exportVocabularyMarkdown(_ sender: NSButton) {
        exportVocabulary(format: .markdown)
    }

    @objc func exportVocabularyCSV(_ sender: NSButton) {
        exportVocabulary(format: .csv)
    }

    enum VocabularyExportFormat {
        case markdown
        case csv

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .csv: return "csv"
            }
        }
    }

    func exportVocabulary(format: VocabularyExportFormat) {
        let records = currentVocabularyExportRecordsForActiveFilter()
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !records.isEmpty else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = "\(safeExportFileName(documentTitleForAI()))-vocabulary.\(format.fileExtension)"
        savePanel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let output: String
                switch format {
                case .markdown:
                    output = self?.vocabularyMarkdown(records) ?? ""
                case .csv:
                    output = self?.vocabularyCSV(records) ?? ""
                }
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func currentVocabularyExportRecordsForActiveFilter() -> [VocabularyExportRecord] {
        let filter = selectedVocabularyListFilter(in: vocabularyPanel?.contentView)
        return vocabularyRecords(currentVocabularyExportRecords, matching: filter)
    }

    func vocabularyMarkdown(_ records: [VocabularyExportRecord]) -> String {
        var lines: [String] = [
            "# \(documentTitleForAI()) \(AppText.localized("背单词", "Vocabulary"))",
            "",
            "- 导出时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))",
            "- 单词数量：\(records.count)",
            ""
        ]
        for record in records {
            lines.append("## \(record.word)")
            lines.append("")
            lines.append("- 位置：\(record.location)")
            if !record.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("- 原文上下文：\(record.context)")
            }
            lines.append("")
            lines.append(vocabularyAnswerBody(record.answer, word: record.word))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func vocabularyCSV(_ records: [VocabularyExportRecord]) -> String {
        var rows = ["Front,Back,Page,Context,Source,Created At"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([
                record.word,
                vocabularyAnswerBody(record.answer, word: record.word),
                record.location,
                record.context,
                documentTitleForAI(),
                formatter.string(from: record.createdAt)
            ].map(csvEscaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    func pdfWordContext(for record: StoredPDFWordRecord) -> String {
        if let context = record.context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            return context
        }
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return "" }
        let pageText = page.string ?? ""
        let selectedText = record.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: pageText, radius: 24) {
            return context
        }
        let expandedBounds = record.bounds.cgRect.insetBy(dx: -120, dy: -36)
        if let nearbyText = page.selection(for: expandedBounds)?.string,
           let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: nearbyText, radius: 24) {
            return context
        }
        return ReaderAIContextBuilder.normalizeWhitespace(page.selection(for: record.bounds.cgRect.insetBy(dx: -80, dy: -24))?.string ?? "")
    }

    func safeExportFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        return trimmed.range(of: #"[A-Za-z0-9\u{4e00}-\u{9fff}]"#, options: .regularExpression) != nil
    }
}
