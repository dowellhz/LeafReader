import Cocoa

final class VocabularySpeakerButton: NSButton {
    var spokenWord: String?

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class VocabularyDetailScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return }
        super.scrollWheel(with: event)
    }
}

final class VocabularyDetailClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

extension ReaderWindowController {
    var vocabularyReviewButtonWidth: CGFloat { 128 }
    var vocabularyListPageSize: Int { 20 }

    func vocabularyPanelBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func vocabularyPrimaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        }
    }

    func vocabularySecondaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        case .eyeCare:
            return theme.secondaryTextColor
        case .dark:
            return NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1)
        }
    }

    func vocabularyBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    func vocabularyCardBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.88, green: 0.83, blue: 0.68, alpha: 1)
        case .dark:
            return NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1)
        }
    }

    func vocabularyCardBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    func vocabularyBodyTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.22, green: 0.25, blue: 0.31, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1)
        case .dark:
            return NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1)
        }
    }

    func vocabularyButtonBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.92, green: 0.87, blue: 0.72, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func vocabularyPrimaryActionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.accentColor
    }

    func vocabularyPrimaryActionTextColor(for theme: ReaderTheme) -> NSColor {
        theme.primaryActionTextColor
    }

    func vocabularyAccentColor(for theme: ReaderTheme) -> NSColor {
        theme.strongAccentColor
    }

    func vocabularySelectionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        vocabularyAccentColor(for: theme).withAlphaComponent(theme == .eyeCare ? 0.24 : 0.20)
    }

    func styleVocabularyActionButton(_ button: ThemedSettingsActionButton, fontSize: CGFloat = 14, isPrimary: Bool = false) {
        let theme = ReaderTheme.selected
        button.fillColor = isPrimary ? vocabularyPrimaryActionBackgroundColor(for: theme) : vocabularyButtonBackgroundColor(for: theme)
        button.strokeColor = isPrimary ? vocabularyPrimaryActionBackgroundColor(for: theme) : vocabularyBorderColor(for: theme)
        button.labelColor = isPrimary ? vocabularyPrimaryActionTextColor(for: theme) : vocabularyPrimaryTextColor(for: theme)
        button.font = AppFont.semibold(ofSize: fontSize)
        button.lineBreakMode = .byTruncatingTail
    }

    func vocabularyActionButton(title: String, target: AnyObject?, action: Selector?, fontSize: CGFloat = 14, isPrimary: Bool = false) -> ThemedSettingsActionButton {
        let button = ThemedSettingsActionButton(title: title, target: target, action: action)
        button.controlSize = .large
        styleVocabularyActionButton(button, fontSize: fontSize, isPrimary: isPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    enum VocabularyFilter: Int {
        case due = 0
        case new = 1
        case all = 2
    }

    @objc func showVocabularyBook() {
        let records: [VocabularyExportRecord]
        if currentDocumentKind == .pdf {
            records = storedWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)"),
                        context: pdfWordContext(for: $0),
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)
                    )
                }
        } else {
            records = storedWebWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("进度 \(Int(($0.scrollProgress * 100).rounded()))%", "\(Int(($0.scrollProgress * 100).rounded()))%"),
                        context: $0.context,
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)
                    )
                }
        }
        let aggregatedRecords = aggregateVocabularyRecords(records)
        guard !aggregatedRecords.isEmpty else {
            NSSound.beep()
            return
        }
        currentVocabularyExportRecords = aggregatedRecords
        vocabularyReviewFilter = .due
        vocabularyReviewIndex = 0
        vocabularyListModeEnabled = false
        vocabularyReviewBatchKeys = []
        resetVocabularyReviewCardState(clearCardKey: true)

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = true

        let theme = ReaderTheme.selected
        let isDark = theme == .dark
        let panelBackground = vocabularyPanelBackgroundColor(for: theme)
        let primaryText = vocabularyPrimaryTextColor(for: theme)
        let secondaryText = vocabularySecondaryTextColor(for: theme)
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = panelBackground.cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = vocabularyBorderColor(for: theme).cgColor
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)
        root.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = root

        let title = NSTextField(labelWithString: AppText.localized("背单词", "Vocabulary Trainer"))
        title.font = AppFont.semibold(ofSize: 20)
        title.textColor = primaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        icon.contentTintColor = vocabularyAccentColor(for: theme)
        icon.imageScaling = .scaleNone
        icon.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = panelBackground
        scrollView.borderType = .noBorder
        scrollView.identifier = NSUserInterfaceItemIdentifier("vocabularyScrollView")
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.wantsLayer = true
        stack.layer?.backgroundColor = panelBackground.cgColor
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("vocabularyStack")
        scrollView.documentView = stack

        let filterControl = SettingsTabsView(
            labels: [
                AppText.localized("背单词", "Review"),
                AppText.localized("复习", "Reviewed"),
                AppText.localized("新词", "New"),
                AppText.localized("全部", "All")
            ],
            selectedIndex: 0
        )
        filterControl.onSelectionChanged = { [weak self] index in
            self?.changeVocabularyTab(index: index)
        }
        filterControl.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: vocabularySummaryText(records: aggregatedRecords, filter: .due))
        summaryLabel.font = AppFont.semibold(ofSize: 13)
        summaryLabel.textColor = secondaryText
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.identifier = NSUserInterfaceItemIdentifier("vocabularySummaryLabel")

        let reviewContainer = NSView()
        reviewContainer.wantsLayer = true
        reviewContainer.layer?.backgroundColor = panelBackground.cgColor
        reviewContainer.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewContainer")
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false

        populateVocabularyStack(stack, records: aggregatedRecords, filter: .due, isDark: isDark)
        populateVocabularyReviewContainer(reviewContainer, records: aggregatedRecords, filter: .due, isDark: isDark, autoPlayNewCard: false)
        scrollView.isHidden = true

        let closeButton = vocabularyActionButton(title: AppText.close, target: self, action: #selector(closeVocabularyBook(_:)))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = vocabularyActionButton(title: AppText.localized("导出 MD", "Export MD"), target: self, action: #selector(exportVocabularyMarkdown(_:)))
        exportMarkdownButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportMarkdownButton")

        let exportCSVButton = vocabularyActionButton(title: AppText.localized("导出 Anki CSV", "Export Anki CSV"), target: self, action: #selector(exportVocabularyCSV(_:)))
        exportCSVButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportCSVButton")

        exportMarkdownButton.isHidden = true
        exportCSVButton.isHidden = true

        for view in [icon, title, filterControl, summaryLabel, reviewContainer, scrollView, exportMarkdownButton, exportCSVButton, closeButton] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: filterControl.leadingAnchor, constant: -16),
            filterControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            filterControl.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            filterControl.widthAnchor.constraint(equalToConstant: 360),
            filterControl.heightAnchor.constraint(equalToConstant: 30),
            summaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            summaryLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            summaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),

            reviewContainer.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            reviewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            reviewContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            reviewContainer.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
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
        reloadVocabularyPanelContent()
        installVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.present(panel, attachedTo: window)
    }
}
