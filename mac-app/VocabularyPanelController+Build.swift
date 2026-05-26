import Cocoa

extension VocabularyPanelController {
    func makePanel(records: [VocabularyExportRecord]) -> NSWindow? {
        guard let owner else { return nil }
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
        let panelBackground = owner.vocabularyPanelBackgroundColor(for: theme)
        let primaryText = owner.vocabularyPrimaryTextColor(for: theme)
        let secondaryText = owner.vocabularySecondaryTextColor(for: theme)
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = panelBackground.cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = owner.vocabularyBorderColor(for: theme).cgColor
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
        icon.contentTintColor = owner.vocabularyAccentColor(for: theme)
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
        filterControl.onSelectionChanged = { [weak owner] index in
            owner?.changeVocabularyTab(index: index)
        }
        filterControl.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: owner.vocabularySummaryText(records: records, filter: .due))
        summaryLabel.font = AppFont.semibold(ofSize: 13)
        summaryLabel.textColor = secondaryText
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.identifier = NSUserInterfaceItemIdentifier("vocabularySummaryLabel")

        let reviewContainer = NSView()
        reviewContainer.wantsLayer = true
        reviewContainer.layer?.backgroundColor = panelBackground.cgColor
        reviewContainer.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewContainer")
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false

        owner.populateVocabularyStack(stack, records: records, filter: .due, isDark: isDark)
        owner.populateVocabularyReviewContainer(reviewContainer, records: records, filter: .due, isDark: isDark, autoPlayNewCard: false)
        scrollView.isHidden = true

        let reviewPriorityPopup = owner.vocabularyReviewPriorityPopup()
        reviewPriorityPopup.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewPriorityPopup")

        let closeButton = owner.vocabularyActionButton(title: AppText.close, target: owner, action: #selector(ReaderWindowController.closeVocabularyBook(_:)))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 MD", "Export MD"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyMarkdown(_:))
        )
        exportMarkdownButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportMarkdownButton")

        let exportCSVButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 Anki CSV", "Export Anki CSV"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyCSV(_:))
        )
        exportCSVButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportCSVButton")

        exportMarkdownButton.isHidden = true
        exportCSVButton.isHidden = true

        for view in [icon, title, filterControl, summaryLabel, reviewContainer, scrollView, reviewPriorityPopup, exportMarkdownButton, exportCSVButton, closeButton] {
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

            reviewPriorityPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            reviewPriorityPopup.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            reviewPriorityPopup.widthAnchor.constraint(equalToConstant: 150),
            reviewPriorityPopup.heightAnchor.constraint(equalToConstant: 36),

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

        return panel
    }
}
