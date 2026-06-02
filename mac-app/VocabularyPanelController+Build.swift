import Cocoa

private struct VocabularyPanelViews {
    let icon: NSImageView
    let title: NSTextField
    let filterControl: SettingsTabsView
    let summaryLabel: NSTextField
    let statsContainer: NSStackView
    let reviewContainer: NSView
    let scrollView: NSScrollView
    let stack: NSStackView
    let reviewPriorityPopup: NSPopUpButton
    let reviewGoalPopup: NSPopUpButton
    let exportMarkdownButton: ThemedSettingsActionButton
    let exportCSVButton: ThemedSettingsActionButton
    let closeButton: ThemedSettingsActionButton
}

extension VocabularyPanelController {
    func makePanel(records: [VocabularyExportRecord]) -> NSWindow? {
        guard let owner else { return nil }
        let panel = makeWindow()
        let theme = ReaderTheme.selected
        let root = makeRootView(for: panel, theme: theme)
        panel.contentView = root

        let views = makePanelViews(owner: owner, records: records, theme: theme)
        addPanelViews(views, to: root)
        installPanelConstraints(views, in: root)
        return panel
    }

    private func makeWindow() -> NSWindow {
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
        return panel
    }

    private func makeRootView(for panel: NSWindow, theme: ReaderTheme) -> NSView {
        guard let owner else { return NSView() }
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = owner.vocabularyPanelBackgroundColor(for: theme).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = owner.vocabularyBorderColor(for: theme).cgColor
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = theme == .dark ? 0.42 : 0.24
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)
        root.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        return root
    }

    private func makePanelViews(
        owner: ReaderWindowController,
        records: [VocabularyExportRecord],
        theme: ReaderTheme
    ) -> VocabularyPanelViews {
        let panelBackground = owner.vocabularyPanelBackgroundColor(for: theme)
        let primaryText = owner.vocabularyPrimaryTextColor(for: theme)
        let secondaryText = owner.vocabularySecondaryTextColor(for: theme)

        let icon = makeHeaderIcon(owner: owner, theme: theme)
        let title = makeTitleLabel(primaryText: primaryText)
        let filterControl = makeFilterControl(owner: owner)
        let summaryLabel = makeSummaryLabel(owner: owner, records: records, secondaryText: secondaryText)
        let statsContainer = makeStatsContainer(owner: owner, records: records, theme: theme)
        let (scrollView, stack) = makeVocabularyList(panelBackground: panelBackground)
        let reviewContainer = makeReviewContainer(panelBackground: panelBackground)
        owner.populateVocabularyStack(stack, records: records, filter: .due, isDark: theme == .dark)
        owner.populateVocabularyReviewContainer(reviewContainer, records: records, filter: .due, isDark: theme == .dark, autoPlayNewCard: false)
        scrollView.isHidden = true

        let reviewPriorityPopup = owner.vocabularyReviewPriorityPopup()
        reviewPriorityPopup.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewPriorityPopup")
        let reviewGoalPopup = owner.vocabularyDailyGoalPopup()
        reviewGoalPopup.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewGoalPopup")

        let closeButton = owner.vocabularyActionButton(title: AppText.close, target: owner, action: #selector(ReaderWindowController.closeVocabularyBook(_:)))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 MD", "Export MD"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyMarkdown(_:))
        )
        exportMarkdownButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportMarkdownButton")
        exportMarkdownButton.isHidden = true

        let exportCSVButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 Anki CSV", "Export Anki CSV"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyCSV(_:))
        )
        exportCSVButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportCSVButton")
        exportCSVButton.isHidden = true

        return VocabularyPanelViews(
            icon: icon,
            title: title,
            filterControl: filterControl,
            summaryLabel: summaryLabel,
            statsContainer: statsContainer,
            reviewContainer: reviewContainer,
            scrollView: scrollView,
            stack: stack,
            reviewPriorityPopup: reviewPriorityPopup,
            reviewGoalPopup: reviewGoalPopup,
            exportMarkdownButton: exportMarkdownButton,
            exportCSVButton: exportCSVButton,
            closeButton: closeButton
        )
    }

    private func makeHeaderIcon(owner: ReaderWindowController, theme: ReaderTheme) -> NSImageView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        icon.contentTintColor = owner.vocabularyAccentColor(for: theme)
        icon.imageScaling = .scaleNone
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }

    private func makeTitleLabel(primaryText: NSColor) -> NSTextField {
        let title = NSTextField(labelWithString: AppText.localized("背单词", "Vocabulary Trainer"))
        title.font = AppFont.semibold(ofSize: 20)
        title.textColor = primaryText
        title.translatesAutoresizingMaskIntoConstraints = false
        return title
    }

    private func makeFilterControl(owner: ReaderWindowController) -> SettingsTabsView {
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
        return filterControl
    }

    private func makeSummaryLabel(
        owner: ReaderWindowController,
        records: [VocabularyExportRecord],
        secondaryText: NSColor
    ) -> NSTextField {
        let summaryLabel = NSTextField(labelWithString: owner.vocabularySummaryText(records: records, filter: .due))
        summaryLabel.font = AppFont.semibold(ofSize: 13)
        summaryLabel.textColor = secondaryText
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.identifier = NSUserInterfaceItemIdentifier("vocabularySummaryLabel")
        return summaryLabel
    }

    private func makeStatsContainer(
        owner: ReaderWindowController,
        records: [VocabularyExportRecord],
        theme: ReaderTheme
    ) -> NSStackView {
        let stats = VocabularyLearningStatsCalculator.stats(records: records)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .height
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.identifier = NSUserInterfaceItemIdentifier(VocabularyLearningStatsPresenter.containerIdentifier)
        stack.translatesAutoresizingMaskIntoConstraints = false

        VocabularyLearningStatsPresenter.items(for: stats)
            .map { vocabularyStatCard(item: $0, owner: owner, theme: theme) }
            .forEach(stack.addArrangedSubview)
        return stack
    }

    private func vocabularyStatCard(
        item: VocabularyLearningStatDisplayItem,
        owner: ReaderWindowController,
        theme: ReaderTheme
    ) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = owner.vocabularyCardBackgroundColor(for: theme).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = owner.vocabularyCardBorderColor(for: theme).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: item.value)
        valueLabel.font = AppFont.semibold(ofSize: 18)
        valueLabel.textColor = owner.vocabularyPrimaryTextColor(for: theme)
        valueLabel.alignment = .center
        valueLabel.identifier = NSUserInterfaceItemIdentifier(item.valueIdentifier)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.font = AppFont.semibold(ofSize: 11)
        titleLabel.textColor = owner.vocabularySecondaryTextColor(for: theme)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(valueLabel)
        card.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8)
        ])
        return card
    }

    private func makeVocabularyList(panelBackground: NSColor) -> (NSScrollView, NSStackView) {
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
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("vocabularyStack")
        scrollView.documentView = stack
        return (scrollView, stack)
    }

    private func makeReviewContainer(panelBackground: NSColor) -> NSView {
        let reviewContainer = NSView()
        reviewContainer.wantsLayer = true
        reviewContainer.layer?.backgroundColor = panelBackground.cgColor
        reviewContainer.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewContainer")
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false
        return reviewContainer
    }

    private func addPanelViews(_ views: VocabularyPanelViews, to root: NSView) {
        [
            views.icon,
            views.title,
            views.filterControl,
            views.summaryLabel,
            views.statsContainer,
            views.reviewContainer,
            views.scrollView,
            views.reviewPriorityPopup,
            views.reviewGoalPopup,
            views.exportMarkdownButton,
            views.exportCSVButton,
            views.closeButton
        ].forEach(root.addSubview)
    }

    private func installPanelConstraints(_ views: VocabularyPanelViews, in root: NSView) {
        NSLayoutConstraint.activate([
            views.icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            views.icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            views.icon.widthAnchor.constraint(equalToConstant: 30),
            views.icon.heightAnchor.constraint(equalToConstant: 30),
            views.title.leadingAnchor.constraint(equalTo: views.icon.trailingAnchor, constant: 12),
            views.title.centerYAnchor.constraint(equalTo: views.icon.centerYAnchor),
            views.title.trailingAnchor.constraint(lessThanOrEqualTo: views.filterControl.leadingAnchor, constant: -16),
            views.filterControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.filterControl.centerYAnchor.constraint(equalTo: views.icon.centerYAnchor),
            views.filterControl.widthAnchor.constraint(equalToConstant: 360),
            views.filterControl.heightAnchor.constraint(equalToConstant: 30),
            views.summaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            views.summaryLabel.topAnchor.constraint(equalTo: views.icon.bottomAnchor, constant: 14),
            views.summaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            views.statsContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.statsContainer.topAnchor.constraint(equalTo: views.summaryLabel.bottomAnchor, constant: 10),
            views.statsContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.statsContainer.heightAnchor.constraint(equalToConstant: 62),

            views.reviewContainer.topAnchor.constraint(equalTo: views.statsContainer.bottomAnchor, constant: 12),
            views.reviewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.reviewContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.reviewContainer.bottomAnchor.constraint(equalTo: views.closeButton.topAnchor, constant: -14),

            views.scrollView.topAnchor.constraint(equalTo: views.statsContainer.bottomAnchor, constant: 12),
            views.scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.scrollView.bottomAnchor.constraint(equalTo: views.closeButton.topAnchor, constant: -14),
            views.stack.topAnchor.constraint(equalTo: views.scrollView.contentView.topAnchor),
            views.stack.leadingAnchor.constraint(equalTo: views.scrollView.contentView.leadingAnchor),
            views.stack.trailingAnchor.constraint(equalTo: views.scrollView.contentView.trailingAnchor),
            views.stack.widthAnchor.constraint(equalTo: views.scrollView.contentView.widthAnchor),

            views.reviewPriorityPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.reviewPriorityPopup.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.reviewPriorityPopup.widthAnchor.constraint(equalToConstant: 150),
            views.reviewPriorityPopup.heightAnchor.constraint(equalToConstant: 36),
            views.reviewGoalPopup.leadingAnchor.constraint(equalTo: views.reviewPriorityPopup.trailingAnchor, constant: 10),
            views.reviewGoalPopup.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.reviewGoalPopup.widthAnchor.constraint(equalToConstant: 112),
            views.reviewGoalPopup.heightAnchor.constraint(equalToConstant: 36),

            views.exportMarkdownButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.exportMarkdownButton.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.exportMarkdownButton.widthAnchor.constraint(equalToConstant: 104),
            views.exportMarkdownButton.heightAnchor.constraint(equalToConstant: 36),
            views.exportCSVButton.leadingAnchor.constraint(equalTo: views.exportMarkdownButton.trailingAnchor, constant: 10),
            views.exportCSVButton.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.exportCSVButton.widthAnchor.constraint(equalToConstant: 132),
            views.exportCSVButton.heightAnchor.constraint(equalToConstant: 36),

            views.closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            views.closeButton.widthAnchor.constraint(equalToConstant: 104),
            views.closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}
