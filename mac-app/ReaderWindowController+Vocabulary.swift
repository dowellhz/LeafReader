import Cocoa

final class VocabularySpeakerButton: NSButton {
    var spokenWord: String?

    override var acceptsFirstResponder: Bool { false }

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

        let title = NSTextField(labelWithString: AppText.localized("本书背单词", "Book Vocabulary Trainer"))
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
        scrollView.identifier = NSUserInterfaceItemIdentifier("vocabularyScrollView")
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("vocabularyStack")
        scrollView.documentView = stack

        let filterControl = NSSegmentedControl(
            labels: [
                AppText.localized("背单词", "Review"),
                AppText.localized("复习", "Reviewed"),
                AppText.localized("新词", "New"),
                AppText.localized("全部", "All")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeVocabularyTab(_:))
        )
        filterControl.selectedSegment = 0
        filterControl.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: vocabularySummaryText(records: aggregatedRecords, filter: .due))
        summaryLabel.font = AppFont.semibold(ofSize: 13)
        summaryLabel.textColor = isDark ? NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.identifier = NSUserInterfaceItemIdentifier("vocabularySummaryLabel")

        let reviewContainer = NSView()
        reviewContainer.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewContainer")
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false

        populateVocabularyStack(stack, records: aggregatedRecords, filter: .due, isDark: isDark)
        populateVocabularyReviewContainer(reviewContainer, records: aggregatedRecords, filter: .due, isDark: isDark, autoPlayNewCard: false)
        scrollView.isHidden = true

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
        exportMarkdownButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportMarkdownButton")
        exportMarkdownButton.translatesAutoresizingMaskIntoConstraints = false

        let exportCSVButton = NSButton(title: AppText.localized("导出 Anki CSV", "Export Anki CSV"), target: self, action: #selector(exportVocabularyCSV(_:)))
        exportCSVButton.bezelStyle = .rounded
        exportCSVButton.controlSize = .large
        exportCSVButton.font = AppFont.semibold(ofSize: 14)
        exportCSVButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportCSVButton")
        exportCSVButton.translatesAutoresizingMaskIntoConstraints = false

        exportMarkdownButton.isHidden = true
        exportCSVButton.isHidden = true

        for view in [icon, title, filterControl, summaryLabel, reviewContainer, scrollView, exportMarkdownButton, exportCSVButton, closeButton] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
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
