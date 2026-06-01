import Cocoa

final class ReadingNotesPanelController: NSObject {
    private enum Metrics {
        static let panelSize = NSSize(width: 560, height: 420)
        static let outerMargin: CGFloat = 28
        static let headerTop: CGFloat = 34
        static let headerLeading: CGFloat = 34
        static let headerIconSize: CGFloat = 30
        static let rowHeight: CGFloat = 74
        static let rowIconSize: CGFloat = 42
        static let rowIconSymbolSize: CGFloat = 18
        static let actionButtonWidth: CGFloat = 88
        static let actionButtonHeight: CGFloat = 32
        static let rowPageWidth: CGFloat = 56
        static let rowDeleteWidth: CGFloat = 48
        static let rowHorizontalInset: CGFloat = 16
        static let rowColumnSpacing: CGFloat = 14
        static let searchHeight: CGFloat = 32
    }

    private enum ActionButtonRole {
        case primary
        case secondary
    }

    var onOpenNote: ((ReadingNote) -> Void)?
    var onDeleteNote: ((ReadingNote) -> Void)?
    var onExport: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var panel: NSWindow?
    private let rootView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: AppText.localized("阅读笔记", "Reading Notes"))
    private let searchField = NSSearchField()
    private let stack = ReadingNotesStackView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private var exportButton: NSButton?
    private var closeButton: NSButton?
    private var notes: [ReadingNote] = []
    private var rows: [ReadingNoteListRowViewModel] = []
    private var searchQuery = ""

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readerThemeDidChange(_:)),
            name: .readerThemeDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(notes: [ReadingNote], parent: NSWindow?) {
        updateData(notes)
        if panel == nil {
            panel = buildPanel()
        }
        resetPanelSize()
        applyTheme(ReaderTheme.selected)
        refreshContent()
        guard let panel else { return }
        center(panel, relativeTo: parent)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
    }

    private func focusSearchField() {
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.makeFirstResponder(self.searchField)
        }
    }

    func update(notes: [ReadingNote]) {
        updateData(notes)
        refreshContent()
    }

    func refreshTheme() {
        applyTheme(ReaderTheme.selected)
        refreshContent()
    }

    func close(attachedTo parent: NSWindow?) {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
        onClose?()
    }

    private func buildPanel() -> NSWindow {
        let panel = ReadingNotesPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        configureRootView(for: panel)

        iconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = AppFont.semibold(ofSize: 20)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = AppFont.semibold(ofSize: 13)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        configureSearchField()

        let scrollView = buildScrollView()
        let exportButton = actionButton(title: AppText.localized("导出 MD", "Export MD"), action: #selector(exportTapped(_:)))
        let closeButton = actionButton(title: AppText.close, action: #selector(closeTapped(_:)))
        self.exportButton = exportButton
        self.closeButton = closeButton

        for view in [iconView, titleLabel, searchField, summaryLabel, scrollView, exportButton, closeButton] {
            rootView.addSubview(view)
        }
        installConstraints(scrollView: scrollView, exportButton: exportButton, closeButton: closeButton)
        applyTheme(ReaderTheme.selected)
        return panel
    }

    private func center(_ panel: NSWindow, relativeTo parent: NSWindow?) {
        guard let parent else {
            panel.center()
            return
        }
        let parentFrame = parent.frame
        let origin = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(clampedOrigin(origin, panelSize: panel.frame.size, visibleFrame: parent.screen?.visibleFrame))
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect?) -> NSPoint {
        guard let visibleFrame else { return origin }
        let minX = visibleFrame.minX + 12
        let maxX = visibleFrame.maxX - panelSize.width - 12
        let minY = visibleFrame.minY + 12
        let maxY = visibleFrame.maxY - panelSize.height - 12
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func resetPanelSize() {
        guard let panel else { return }
        panel.setContentSize(Metrics.panelSize)
        rootView.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
    }

    private func configureRootView(for panel: NSPanel) {
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 16
        rootView.layer?.borderWidth = 1
        rootView.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        rootView.autoresizingMask = [.width, .height]
        panel.contentView = rootView
    }

    private func buildScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        return scrollView
    }

    private func installConstraints(scrollView: NSScrollView, exportButton: NSButton, closeButton: NSButton) {
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Metrics.headerTop),
            iconView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.headerLeading),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.headerIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.headerIconSize),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: exportButton.leadingAnchor, constant: -18),
            searchField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.headerLeading),
            searchField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.headerLeading),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.searchHeight),
            summaryLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            summaryLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.headerLeading),
            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.outerMargin),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.outerMargin),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Metrics.outerMargin),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            closeButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Metrics.headerTop - 2),
            closeButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.headerLeading),
            closeButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            closeButton.heightAnchor.constraint(equalToConstant: Metrics.actionButtonHeight),
            exportButton.topAnchor.constraint(equalTo: closeButton.topAnchor),
            exportButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            exportButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            exportButton.heightAnchor.constraint(equalToConstant: Metrics.actionButtonHeight)
        ])
    }

    private func refreshContent() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        summaryLabel.stringValue = summaryText()
        guard !rows.isEmpty else {
            stack.addArrangedSubview(emptyStateLabel())
            return
        }
        for rowViewModel in rows {
            let row = noteRow(rowViewModel)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func noteRow(_ rowViewModel: ReadingNoteListRowViewModel) -> NSView {
        let theme = ReaderTheme.selected
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true

        let iconContainer = rowIconContainer(theme: theme)
        let icon = rowIcon(theme: theme)
        iconContainer.addSubview(icon)

        let locationLabel = NSTextField(labelWithString: rowViewModel.locationText)
        locationLabel.font = AppFont.semibold(ofSize: 15)
        locationLabel.textColor = ReadingNoteTheme.primaryText(theme)
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let quoteLabel = NSTextField(labelWithString: rowViewModel.titleText)
        quoteLabel.font = NSFont.systemFont(ofSize: 14)
        quoteLabel.textColor = ReadingNoteTheme.primaryText(theme)
        quoteLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.maximumNumberOfLines = 2
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let openButton = rowOpenButton(noteID: rowViewModel.id)
        let deleteButton = rowDeleteButton(noteID: rowViewModel.id, theme: theme)

        for view in [iconContainer, locationLabel, quoteLabel, openButton, deleteButton] {
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Metrics.rowHorizontalInset),
            iconContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Metrics.rowIconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Metrics.rowIconSize),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            locationLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: Metrics.rowColumnSpacing),
            locationLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            locationLabel.widthAnchor.constraint(equalToConstant: Metrics.rowPageWidth),
            quoteLabel.leadingAnchor.constraint(equalTo: locationLabel.trailingAnchor, constant: Metrics.rowColumnSpacing),
            quoteLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -Metrics.rowColumnSpacing),
            quoteLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openButton.topAnchor.constraint(equalTo: row.topAnchor),
            openButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            openButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Metrics.rowHorizontalInset),
            deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: Metrics.rowDeleteWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        return row
    }

    private func rowIconContainer(theme: ReaderTheme) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = ReadingNoteTheme.insetBackground(theme).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func rowIcon(theme: ReaderTheme) -> NSImageView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.rowIconSymbolSize, weight: .semibold))
        icon.contentTintColor = ReadingNoteTheme.accent(theme)
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }

    private func rowOpenButton(noteID: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(noteTapped(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(noteID)
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func rowDeleteButton(noteID: String, theme: ReaderTheme) -> NSButton {
        let button = NSButton(title: AppText.localized("删除", "Delete"), target: self, action: #selector(deleteTapped(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(noteID)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 13)
        button.contentTintColor = ReadingNoteTheme.secondaryText(theme)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func actionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.font = AppFont.semibold(ofSize: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func emptyStateLabel() -> NSTextField {
        let text = searchQuery.isEmpty
            ? AppText.localized("当前书还没有阅读笔记。", "No reading notes for this book yet.")
            : AppText.localized("没有匹配的阅读笔记。", "No matching reading notes.")
        let empty = NSTextField(labelWithString: text)
        empty.font = NSFont.systemFont(ofSize: 15)
        empty.textColor = ReadingNoteTheme.secondaryText(ReaderTheme.selected)
        return empty
    }

    @objc private func noteTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let note = notes.first(where: { $0.id == id }) else { return }
        onOpenNote?(note)
    }

    @objc private func exportTapped(_ sender: NSButton) {
        onExport?()
    }

    @objc private func deleteTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let note = notes.first(where: { $0.id == id }) else { return }
        onDeleteNote?(note)
    }

    @objc private func closeTapped(_ sender: NSButton) {
        close(attachedTo: panel?.parent)
    }

    @objc private func readerThemeDidChange(_ notification: Notification) {
        applyTheme(ReaderTheme.selected)
        refreshContent()
    }

    private func applyTheme(_ theme: ReaderTheme) {
        guard panel != nil else { return }
        panel?.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        rootView.layer?.backgroundColor = ReadingNoteTheme.panelBackground(theme).cgColor
        rootView.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        iconView.contentTintColor = ReadingNoteTheme.accent(theme)
        titleLabel.textColor = ReadingNoteTheme.primaryText(theme)
        searchField.textColor = ReadingNoteTheme.primaryText(theme)
        summaryLabel.textColor = ReadingNoteTheme.secondaryText(theme)
        styleActionButton(exportButton, role: .primary, theme: theme)
        styleActionButton(closeButton, role: .secondary, theme: theme)
    }

    private func styleActionButton(_ button: NSButton?, role: ActionButtonRole, theme: ReaderTheme) {
        guard let button else { return }
        switch role {
        case .primary:
            button.layer?.backgroundColor = ReadingNoteTheme.accent(theme).cgColor
            button.contentTintColor = theme == .dark ? ReadingNoteTheme.primaryText(theme) : .white
        case .secondary:
            button.layer?.backgroundColor = ReadingNoteTheme.secondaryButtonBackground(theme).cgColor
            button.contentTintColor = ReadingNoteTheme.primaryText(theme)
        }
    }

    private func updateData(_ notes: [ReadingNote]) {
        self.notes = ReadingNoteListPresenter.sortedNotes(notes)
        applySearchQuery(searchQuery)
    }

    private func configureSearchField() {
        searchField.placeholderString = AppText.localized("搜索笔记", "Search notes")
        searchField.font = AppFont.semibold(ofSize: 13)
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applySearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = ReadingNoteListPresenter.rows(for: notes, query: searchQuery)
    }

    private func summaryText() -> String {
        guard !searchQuery.isEmpty else {
            return ReadingNoteListPresenter.summaryText(noteCount: rows.count)
        }
        return AppText.localized(
            "找到 \(rows.count) / \(notes.count) 条笔记",
            "\(rows.count) of \(notes.count) note(s)"
        )
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applySearchQuery(sender.stringValue)
        refreshContent()
    }

}

private final class ReadingNotesStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class ReadingNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
