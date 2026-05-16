import Cocoa
import PDFKit

extension ReaderWindowController {
    @objc func showVocabularyBook() {
        let records: [VocabularyExportRecord]
        if currentDocumentKind == .pdf {
            records = storedWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)"),
                        context: pdfWordContext(for: $0),
                        createdAt: $0.createdAt
                    )
                }
        } else {
            records = storedWebWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("进度 \(Int(($0.scrollProgress * 100).rounded()))%", "\(Int(($0.scrollProgress * 100).rounded()))%"),
                        context: $0.context,
                        createdAt: $0.createdAt
                    )
                }
        }
        let aggregatedRecords = aggregateVocabularyRecords(records)
        guard !aggregatedRecords.isEmpty else {
            NSSound.beep()
            return
        }
        currentVocabularyExportRecords = aggregatedRecords

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = true

        let isDark = ReaderTheme.selected == .dark
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = (isDark ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1) : NSColor.white).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = (isDark ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1) : NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)).cgColor
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)
        root.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = root

        let title = NSTextField(labelWithString: AppText.localized("本书单词本", "Book Vocabulary"))
        title.font = AppFont.semibold(ofSize: 20)
        title.textColor = isDark ? NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1) : NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "text.book.closed.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = NSColor(red: 0.16, green: 0.45, blue: 0.95, alpha: 1)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for record in aggregatedRecords.prefix(120) {
            stack.addArrangedSubview(vocabularyCard(word: record.word, answer: record.answer, location: record.location, isDark: isDark))
        }

        let closeButton = NSButton(title: AppText.close, target: nil, action: nil)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large
        closeButton.font = AppFont.semibold(ofSize: 14)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeVocabularyBook(_:))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = NSButton(title: AppText.localized("导出 MD", "Export MD"), target: self, action: #selector(exportVocabularyMarkdown(_:)))
        exportMarkdownButton.bezelStyle = .rounded
        exportMarkdownButton.controlSize = .large
        exportMarkdownButton.font = AppFont.semibold(ofSize: 14)
        exportMarkdownButton.translatesAutoresizingMaskIntoConstraints = false

        let exportCSVButton = NSButton(title: AppText.localized("导出 Anki CSV", "Export Anki CSV"), target: self, action: #selector(exportVocabularyCSV(_:)))
        exportCSVButton.bezelStyle = .rounded
        exportCSVButton.controlSize = .large
        exportCSVButton.font = AppFont.semibold(ofSize: 14)
        exportCSVButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [icon, title, scrollView, exportMarkdownButton, exportCSVButton, closeButton] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            exportMarkdownButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            exportMarkdownButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            exportMarkdownButton.widthAnchor.constraint(equalToConstant: 104),
            exportMarkdownButton.heightAnchor.constraint(equalToConstant: 36),
            exportCSVButton.leadingAnchor.constraint(equalTo: exportMarkdownButton.trailingAnchor, constant: 10),
            exportCSVButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            exportCSVButton.widthAnchor.constraint(equalToConstant: 132),
            exportCSVButton.heightAnchor.constraint(equalToConstant: 36),

            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            closeButton.widthAnchor.constraint(equalToConstant: 104),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        vocabularyPanel = panel
        installVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.present(panel, attachedTo: window)
    }

    func aggregateVocabularyRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        var order: [String] = []
        var grouped: [String: [VocabularyExportRecord]] = [:]
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = record.word
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(record)
        }

        return order.compactMap { key in
            guard let group = grouped[key], let first = group.first else { return nil }
            var seenLocations = Set<String>()
            let locations = group.map(\.location).filter { location in
                guard !seenLocations.contains(location) else { return false }
                seenLocations.insert(location)
                return true
            }
            let locationText: String
            if group.count > 1 {
                locationText = AppText.localized(
                    "出现 \(group.count) 次：\(locations.prefix(6).joined(separator: "、"))",
                    "\(group.count) occurrences: \(locations.prefix(6).joined(separator: ", "))"
                )
            } else {
                locationText = first.location
            }
            let context = group
                .map(\.context)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            let answer = group
                .map(\.answer)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? first.answer
            return VocabularyExportRecord(
                word: first.word,
                answer: answer,
                location: locationText,
                context: context,
                createdAt: first.createdAt
            )
        }
    }

    @objc func closeVocabularyBook(_ sender: NSButton) {
        guard sender.identifier?.rawValue == "closeVocabularyBook",
              let panel = sender.window else { return }
        closeVocabularyPanel(panel)
    }

    func closeVocabularyPanel(_ panel: NSWindow) {
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
        let records = currentVocabularyExportRecords
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
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

    func vocabularyMarkdown(_ records: [VocabularyExportRecord]) -> String {
        var lines: [String] = [
            "# \(documentTitleForAI()) 单词本",
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

    func vocabularyCard(word: String, answer: String, location: String, isDark: Bool) -> NSView {
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
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let locationLabel = NSTextField(labelWithString: location)
        locationLabel.font = AppFont.semibold(ofSize: 12)
        locationLabel.textColor = isDark ? NSColor(red: 0.56, green: 0.63, blue: 0.72, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        locationLabel.alignment = .right
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let answerColor = isDark ? NSColor(red: 0.76, green: 0.80, blue: 0.86, alpha: 1) : NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1)
        let answerBody = vocabularyAnswerBody(answer, word: word)
        let answerLabel = NSTextField(labelWithAttributedString: MarkdownRenderer.render(String(answerBody.prefix(900)), fontSize: 13, textColor: answerColor))
        answerLabel.maximumNumberOfLines = 0
        answerLabel.lineBreakMode = .byWordWrapping
        answerLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [bullet, wordLabel, locationLabel, answerLabel] {
            card.addSubview(view)
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 516),
            bullet.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            bullet.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            wordLabel.leadingAnchor.constraint(equalTo: bullet.trailingAnchor, constant: 8),
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            locationLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            locationLabel.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: locationLabel.leadingAnchor, constant: -12),
            answerLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 10),
            answerLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            answerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            answerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    func vocabularyAnswerBody(_ answer: String, word: String) -> String {
        var lines = answer.components(separatedBy: .newlines)
        let normalizedWord = normalizeVocabularyHeading(word)
        while let first = lines.first {
            let normalizedFirst = normalizeVocabularyHeading(first)
            if normalizedFirst.isEmpty {
                lines.removeFirst()
                continue
            }
            if normalizedFirst == normalizedWord {
                lines.removeFirst()
                continue
            }
            break
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizeVocabularyHeading(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\*\*(.*)\*\*$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^__(.*)__$"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
            .lowercased()
    }

    func persistSelectedWordIfNeeded(_ selection: PDFSelection?, text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              let selection,
              let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }

        let selectionBounds = selection.bounds(for: page)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: selectionBounds,
            queryText: text
        ) ?? selectionBounds.insetBy(dx: -1.5, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            return existing.id
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let record = StoredPDFWordRecord(
                id: UUID().uuidString,
                word: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageIndex: pageIndex,
                bounds: StoredPDFWordRect(bounds),
                context: contextForCurrentSelection(selectedText: text),
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date()
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecords()
            return record.id
        }

        let id = UUID().uuidString
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: contextForCurrentSelection(selectedText: text),
            createdAt: Date()
        )
        return id
    }

    func persistSelectedWebWordIfNeeded(text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = currentWebSelectionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = webWordRecordStore?.existingRecord(in: storedWebWordRecords, word: word, context: context) {
            return existing.id
        }
        if let reusable = reusableWebWordRecord(for: word) {
            let record = StoredWebWordRecord(
                id: UUID().uuidString,
                word: word,
                context: context,
                scrollProgress: webScrollProgress,
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date()
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecords()
            restoreStoredWebWordHighlights()
            return record.id
        }

        let id = UUID().uuidString
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            scrollProgress: webScrollProgress,
            createdAt: Date()
        )
        return id
    }

    func precisePDFSelectionBounds(page: PDFPage, originalBounds: CGRect, queryText: String) -> CGRect? {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 80,
              let pageText = page.string,
              !pageText.isEmpty else {
            return nil
        }

        let candidates = pdfTextRanges(matching: normalizedQuery, in: pageText)
        guard !candidates.isEmpty else { return nil }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestBounds: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for range in candidates {
            guard let candidateSelection = page.selection(for: range) else { continue }
            let candidateBounds = candidateSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
            guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }

            let intersectsOriginal = originalBounds.insetBy(dx: -8, dy: -6).intersects(candidateBounds)
            let candidateCenter = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
            let distance = hypot(candidateCenter.x - originalCenter.x, candidateCenter.y - originalCenter.y)
            let score = intersectsOriginal ? distance : distance + 10_000
            if score < bestScore {
                bestScore = score
                bestBounds = candidateBounds
            }
        }

        return bestBounds
    }

    func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        let words = query.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: #"\s+"#)
        let pattern: String
        if words.count == 1 {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        } else {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)).map(\.range)
    }

    func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            pendingPDFWordRecords.removeValue(forKey: linkID)
            pendingWebWordRecords.removeValue(forKey: linkID)
            return
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWordRecords[index].question = question
            storedWordRecords[index].answer = trimmedAnswer
            saveStoredWordRecords()
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWebWordRecords[index].question = question
            storedWebWordRecords[index].answer = trimmedAnswer
            saveStoredWebWordRecords()
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                word: pending.word,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecords()
            return
        }

        if let pending = pendingWebWordRecords.removeValue(forKey: linkID) {
            let record = StoredWebWordRecord(
                id: pending.id,
                word: pending.word,
                context: pending.context,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecords()
            restoreStoredWebWordHighlights()
        }
    }

    func discardPendingLinkedWord(linkID: String) {
        pendingPDFWordRecords.removeValue(forKey: linkID)
        pendingWebWordRecords.removeValue(forKey: linkID)
    }

    func linkedWordAnswer(for linkID: String) -> String? {
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        return nil
    }

    func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWebWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        for record in storedWordRecords {
            addStoredWordAnnotation(record)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return }
        let key = pdfWordRecordStore?.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            ?? "\(record.pageIndex):\(Int(record.bounds.x.rounded())):\(Int(record.bounds.y.rounded())):\(Int(record.bounds.width.rounded())):\(Int(record.bounds.height.rounded()))"
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: record.bounds.cgRect, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
    }

    func restoreStoredWebWordHighlights() {
        guard currentDocumentKind != .pdf, !storedWebWordRecords.isEmpty else { return }
        let payload = storedWebWordRecords.map {
            [
                "id": $0.id,
                "word": $0.word,
                "context": $0.context
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreWordHighlights(\(json));")
    }

    func clearCurrentBookWordRecords() {
        if currentDocumentKind == .pdf {
            clearCurrentPDFWordRecords()
        } else {
            clearCurrentWebWordRecords()
        }
        aiPanel.loadLinkedWordBubbles([])
    }

    func clearCurrentPDFWordRecords() {
        guard !storedWordRecords.isEmpty else { return }
        for record in storedWordRecords {
            guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
            for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                page.removeAnnotation(annotation)
            }
        }
        storedWordRecords.removeAll()
        highlightedSelectionKeys.removeAll()
        saveStoredWordRecords()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func clearCurrentWebWordRecords() {
        guard !storedWebWordRecords.isEmpty else { return }
        storedWebWordRecords.removeAll()
        saveStoredWebWordRecords()
        let script = """
        (() => {
          document.querySelectorAll('span.leaf-reader-linked-word').forEach((span) => {
            const parent = span.parentNode;
            if (!parent) return;
            while (span.firstChild) parent.insertBefore(span.firstChild, span);
            parent.removeChild(span);
            parent.normalize();
          });
        })();
        """
        webView.evaluateJavaScript(script)
    }

    func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        pdfWordRecordStore?.load() ?? []
    }

    func saveStoredWordRecords() {
        pdfWordRecordStore?.save(storedWordRecords)
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    func saveStoredWebWordRecords() {
        webWordRecordStore?.save(storedWebWordRecords)
    }

    func storedWordID(at event: NSEvent) -> String? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)

        if let annotation = page.annotation(at: pointOnPage),
           let id = storedWordID(from: annotation) {
            return id
        }

        return page.annotations
            .first { annotation in
                annotation.bounds.contains(pointOnPage) && storedWordID(from: annotation) != nil
            }
            .flatMap(storedWordID(from:))
    }

    func storedWordID(from annotation: PDFAnnotation) -> String? {
        guard let contents = annotation.contents,
              contents.hasPrefix("leaf-word:") else {
            return nil
        }
        return String(contents.dropFirst("leaf-word:".count))
    }

    func jumpToStoredLinkedWord(linkID: String) {
        if linkID.hasPrefix("document-source:") {
            let rawIndex = String(linkID.dropFirst("document-source:".count))
            if let index = Int(rawIndex) {
                jumpToDocumentSource(index: index)
            }
            return
        }
        if linkID.hasPrefix("pdf-page:") {
            let rawPage = String(linkID.dropFirst("pdf-page:".count))
            if let pageIndex = Int(rawPage) {
                jumpToPDFPage(index: pageIndex)
            }
            return
        }
        if storedWebWordRecords.contains(where: { $0.id == linkID }) {
            jumpToStoredWebWord(linkID: linkID)
            return
        }
        jumpToStoredPDFWord(linkID: linkID)
    }

    func jumpToStoredPDFWord(linkID: String) {
        guard let record = storedWordRecords.first(where: { $0.id == linkID }),
              let page = pdfView.document?.page(at: record.pageIndex) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: record.bounds.cgRect.minX, y: record.bounds.cgRect.maxY + 80)
        )
        pdfView.go(to: destination)
        lastPageIndex = record.pageIndex
        updatePageLabel()
        saveSession()
    }

    func jumpToStoredWebWord(linkID: String) {
        guard let record = storedWebWordRecords.first(where: { $0.id == linkID }) else { return }
        setAIPanelCollapsed(false, animated: true)
        webView.evaluateJavaScript("window.leafReaderScrollToWord(\(jsStringLiteral(linkID)), \(record.scrollProgress));")
    }

    func selectStoredLinkedWord(linkID: String) {
        guard storedWordRecords.contains(where: { $0.id == linkID })
                || storedWebWordRecords.contains(where: { $0.id == linkID }) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        aiPanel.scrollToLinkedBubble(id: linkID)
    }

}
