import Cocoa
import UniformTypeIdentifiers

final class ReadingNotePanelController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private enum Metrics {
        static let panelOuterMargin: CGFloat = 22
        static let metadataHorizontalInset: CGFloat = 26
        static let metadataHeight: CGFloat = 42
        static let editorToolbarHeight: CGFloat = 52
        static let floatingToolbarInset: CGFloat = 8
        static let topIconPointSize: CGFloat = 17
    }
    static let askInputForwardedShortcutKeys: Set<String> = ["a", "c", "x", "v"]

    struct AskRequest {
        let question: String
        let selectedText: String
    }

    let textView = ReadingNoteTextView()
    let aiRunner = AITextActionRunner()
    let aiToolbarContainer = NSView()
    private let aiToolbar = NSStackView()
    private let explainButton = NSButton(title: AppText.localized("解析", "Explain"), target: nil, action: nil)
    private let translateButton = NSButton(title: AppText.localized("翻译", "Translate"), target: nil, action: nil)
    private let summarizeButton = NSButton(title: AppText.localized("总结", "Summarize"), target: nil, action: nil)
    private let polishButton = NSButton(title: AppText.localized("整理", "Organize"), target: nil, action: nil)
    private let askButton = NSButton(title: AppText.localized("问 AI", "Ask AI"), target: nil, action: nil)
    let askInputContainer = NSView()
    let askInputField = ReadingNoteAskTextField(string: "")
    let askSendButton = NSButton(title: "", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")
    let wordCountLabel = NSTextField(labelWithString: "")
    let rootView = NSView()
    let titleIconView = NSImageView()
    let metadataView = NSView()
    let editorContainer = NSView()
    var topIconButtons: [NSButton] = []
    var aiActionButtons: [NSButton] {
        [explainButton, translateButton, summarizeButton, polishButton, askButton]
    }
    var pendingAskSelectedText = ""
    var aiPlaceholderDisplayText: String?
    private weak var scrollView: NSScrollView?
    var askInputKeyMonitor: Any?
    var isAskInputVisible: Bool {
        !askInputContainer.isHidden
    }
    private var note: ReadingNote
    private let onSave: (ReadingNote) -> Void
    private let onClose: (String) -> Void
    private let onShowNotes: () -> Void
    private let onExportNote: (ReadingNote) -> Void
    private let onDeleteNote: (ReadingNote) -> Void
    let onDocumentQuestionPrompt: DocumentQuestionPromptHandler?
    private var savesOnClose = true
    private var autoSaveWorkItem: DispatchWorkItem?

    init(
        note: ReadingNote,
        onSave: @escaping (ReadingNote) -> Void,
        onClose: @escaping (String) -> Void,
        onShowNotes: @escaping () -> Void,
        onExportNote: @escaping (ReadingNote) -> Void,
        onDeleteNote: @escaping (ReadingNote) -> Void,
        onDocumentQuestionPrompt: DocumentQuestionPromptHandler? = nil
    ) {
        self.note = note
        self.onSave = onSave
        self.onClose = onClose
        self.onShowNotes = onShowNotes
        self.onExportNote = onExportNote
        self.onDeleteNote = onDeleteNote
        self.onDocumentQuestionPrompt = onDocumentQuestionPrompt
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("阅读笔记", "Reading Note")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 520, height: 400)
        super.init(window: panel)
        panel.delegate = self
        buildContent(in: panel)
        applyTheme(ReaderTheme.selected)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readerThemeDidChange(_:)),
            name: .readerThemeDidChange,
            object: nil
        )
        installAskInputKeyMonitor()
        refreshAIToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let askInputKeyMonitor {
            NSEvent.removeMonitor(askInputKeyMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func show(relativeTo parent: NSWindow?) {
        guard let window else { return }
        if let parent {
            let parentFrame = parent.frame
            let origin = NSPoint(
                x: parentFrame.midX - window.frame.width / 2,
                y: parentFrame.midY - window.frame.height / 2
            )
            window.setFrameOrigin(origin)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            window.parent?.removeChildWindow(window)
        }
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        if savesOnClose {
            save()
        }
        onClose(note.id)
    }

    func refreshTheme() {
        applyTheme(ReaderTheme.selected)
        renderMarkdownIntoEditor(markdownFromEditor())
        refreshAIToolbar()
    }

    func textDidChange(_ notification: Notification) {
        scheduleAutoSave()
        updateWordCount()
        refreshAIToolbar()
    }

    func closeWithoutSaving() {
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        savesOnClose = false
        close()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshAIToolbar()
    }

    private func buildContent(in panel: NSPanel) {
        rootView.wantsLayer = true
        rootView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = rootView

        configureAIToolbar()
        configureAskInput()
        aiActionButtons.forEach {
            configureAIButton($0)
            aiToolbar.addArrangedSubview($0)
        }
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        wordCountLabel.font = AppFont.semibold(ofSize: 12)
        wordCountLabel.alignment = .right
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        self.scrollView = scrollView

        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        renderMarkdownIntoEditor(note.markdown)
        textView.delegate = self
        textView.onSelectionChanged = { [weak self] in
            self?.refreshAIToolbar()
        }
        textView.onSlashCommand = { [weak self] in
            self?.runSlashContinuation()
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 22, height: 22)
        scrollView.documentView = textView

        let title = NSTextField(labelWithString: AppText.localized("阅读笔记", "Reading Note"))
        title.font = AppFont.semibold(ofSize: 19)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.image = NSImage(systemSymbolName: "pencil.and.list.clipboard", accessibilityDescription: nil)
        titleIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        titleIconView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let titleStack = NSStackView(views: [titleIconView, title])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let listButton = iconButton(
            symbol: "sidebar.right",
            action: #selector(showNotesTapped(_:)),
            pointSize: Metrics.topIconPointSize
        )
        let moreButton = iconButton(
            symbol: "ellipsis.curlybraces",
            action: #selector(moreTapped(_:)),
            pointSize: Metrics.topIconPointSize
        )
        topIconButtons = [listButton, moreButton]
        let topActions = NSStackView(views: [listButton, moreButton])
        topActions.orientation = .horizontal
        topActions.alignment = .centerY
        topActions.spacing = 8
        topActions.translatesAutoresizingMaskIntoConstraints = false

        metadataView.wantsLayer = true
        metadataView.translatesAutoresizingMaskIntoConstraints = false
        let bookMeta = metadataItem(title: AppText.localized("书籍", "Book"), value: note.documentTitle)
        let locationMeta = metadataItem(title: AppText.localized("位置", "Location"), value: noteLocationText())
        let createdMeta = metadataItem(title: AppText.localized("创建时间", "Created"), value: createdAtText())
        let metadataStack = NSStackView(views: [bookMeta, locationMeta, createdMeta])
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .centerY
        metadataStack.distribution = .fill
        metadataStack.spacing = 18
        metadataStack.translatesAutoresizingMaskIntoConstraints = false
        metadataView.addSubview(metadataStack)

        editorContainer.wantsLayer = true
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        let editorToolbar = buildEditorToolbar()
        editorContainer.addSubview(scrollView)
        editorContainer.addSubview(editorToolbar)
        editorContainer.addSubview(wordCountLabel)

        rootView.addSubview(titleStack)
        rootView.addSubview(topActions)
        rootView.addSubview(metadataView)
        rootView.addSubview(editorContainer)
        rootView.addSubview(statusLabel)
        rootView.addSubview(aiToolbarContainer)
        rootView.addSubview(askInputContainer)
        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            titleStack.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            topActions.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            topActions.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor),

            metadataView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 74),
            metadataView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.panelOuterMargin),
            metadataView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.panelOuterMargin),
            metadataView.heightAnchor.constraint(equalToConstant: Metrics.metadataHeight),
            metadataStack.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor, constant: Metrics.metadataHorizontalInset),
            metadataStack.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor, constant: -Metrics.metadataHorizontalInset),
            metadataStack.centerYAnchor.constraint(equalTo: metadataView.centerYAnchor),
            bookMeta.widthAnchor.constraint(lessThanOrEqualTo: metadataStack.widthAnchor, multiplier: 0.3),

            editorContainer.topAnchor.constraint(equalTo: metadataView.bottomAnchor, constant: 10),
            editorContainer.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -42),

            scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editorToolbar.topAnchor),
            editorToolbar.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorToolbar.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorToolbar.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            editorToolbar.heightAnchor.constraint(equalToConstant: Metrics.editorToolbarHeight),
            statusLabel.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor, constant: -6),
            statusLabel.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -9),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
            wordCountLabel.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -20),
            wordCountLabel.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            wordCountLabel.widthAnchor.constraint(equalToConstant: 52)
        ])
        updateWordCount()
        DispatchQueue.main.async { [weak self] in
            self?.textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func metadataItem(title: String, value: String) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = AppFont.semibold(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = AppFont.semibold(ofSize: 12)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func buildEditorToolbar() -> NSStackView {
        let undo = iconButton(symbol: "arrow.uturn.backward", action: #selector(undoTapped(_:)))
        let redo = iconButton(symbol: "arrow.uturn.forward", action: #selector(redoTapped(_:)))
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let bold = textButton(title: "B", action: #selector(boldTapped(_:)))
        let italic = textButton(title: "I", action: #selector(italicTapped(_:)))
        italic.font = NSFontManager.shared.convert(AppFont.semibold(ofSize: 16), toHaveTrait: .italicFontMask)
        let list = iconButton(symbol: "list.bullet", action: #selector(listTapped(_:)))
        let check = iconButton(symbol: "checklist", action: #selector(checklistTapped(_:)))
        let image = iconButton(symbol: "photo", action: #selector(imageTapped(_:)))
        let stack = NSStackView(views: [undo, redo, separator, bold, italic, list, check, image])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 86)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func configureAIToolbar() {
        aiToolbarContainer.isHidden = true
        aiToolbarContainer.wantsLayer = true
        aiToolbarContainer.layer?.cornerRadius = 9
        aiToolbarContainer.layer?.shadowOpacity = 0.16
        aiToolbarContainer.layer?.shadowRadius = 12
        aiToolbarContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        aiToolbarContainer.frame = NSRect(x: 0, y: 0, width: 318, height: 38)

        aiToolbar.orientation = .horizontal
        aiToolbar.alignment = .centerY
        aiToolbar.distribution = .fillEqually
        aiToolbar.spacing = 4
        aiToolbar.edgeInsets = NSEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        aiToolbar.translatesAutoresizingMaskIntoConstraints = false
        aiToolbarContainer.addSubview(aiToolbar)
        NSLayoutConstraint.activate([
            aiToolbar.topAnchor.constraint(equalTo: aiToolbarContainer.topAnchor),
            aiToolbar.leadingAnchor.constraint(equalTo: aiToolbarContainer.leadingAnchor),
            aiToolbar.trailingAnchor.constraint(equalTo: aiToolbarContainer.trailingAnchor),
            aiToolbar.bottomAnchor.constraint(equalTo: aiToolbarContainer.bottomAnchor)
        ])
    }

    private func configureAskInput() {
        setAskInputVisible(false)
        askInputContainer.wantsLayer = true
        askInputContainer.layer?.cornerRadius = 9
        askInputContainer.layer?.shadowOpacity = 0.16
        askInputContainer.layer?.shadowRadius = 12
        askInputContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        askInputContainer.frame = NSRect(x: 0, y: 0, width: 340, height: 42)

        askInputField.placeholderString = AppText.localized("输入问题", "Ask about the selection")
        askInputField.font = NSFont.systemFont(ofSize: 14)
        askInputField.isBordered = false
        askInputField.drawsBackground = false
        askInputField.focusRingType = .none
        askInputField.target = self
        askInputField.action = #selector(submitAskQuestion(_:))
        askInputField.translatesAutoresizingMaskIntoConstraints = false

        askSendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        askSendButton.isBordered = false
        askSendButton.target = self
        askSendButton.action = #selector(submitAskQuestion(_:))
        askSendButton.translatesAutoresizingMaskIntoConstraints = false

        askInputContainer.addSubview(askInputField)
        askInputContainer.addSubview(askSendButton)
        NSLayoutConstraint.activate([
            askInputField.leadingAnchor.constraint(equalTo: askInputContainer.leadingAnchor, constant: 12),
            askInputField.trailingAnchor.constraint(equalTo: askSendButton.leadingAnchor, constant: -8),
            askInputField.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.trailingAnchor.constraint(equalTo: askInputContainer.trailingAnchor, constant: -10),
            askSendButton.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.widthAnchor.constraint(equalToConstant: 26),
            askSendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func configureAIButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.font = AppFont.semibold(ofSize: 13)
        button.target = self
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        switch button {
        case explainButton:
            button.action = #selector(explainSelection(_:))
        case translateButton:
            button.action = #selector(translateSelection(_:))
        case summarizeButton:
            button.action = #selector(summarizeSelection(_:))
        case polishButton:
            button.action = #selector(polishSelection(_:))
        case askButton:
            button.action = #selector(showAskInput(_:))
        default:
            break
        }
    }

    private func iconButton(symbol: String, action: Selector, pointSize: CGFloat = 15) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        let button = ReadingNoteIconButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func textButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    func save() {
        note.markdown = markdownFromEditor()
        note.updatedAt = Date()
        onSave(note)
    }

    func updateWordCount() {
        let count = textView.string.trimmingCharacters(in: .whitespacesAndNewlines).count
        wordCountLabel.stringValue = AppText.localized("\(count) 字", "\(count) chars")
    }

    private func noteLocationText() -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("Page \(first.pageIndex + 1)", "Page \(first.pageIndex + 1)")
        }
        let percent = Int((note.locator.webAnchor?.scrollProgress ?? 0) * 100)
        return AppText.localized("网页位置 \(percent)%", "Web \(percent)%")
    }

    private func createdAtText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: note.createdAt)
    }

    private func scheduleAutoSave() {
        autoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        autoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @objc private func scrollBoundsDidChange(_ notification: Notification) {
        refreshAIToolbar()
    }

    @objc private func readerThemeDidChange(_ notification: Notification) {
        refreshTheme()
    }

    @objc private func showNotesTapped(_ sender: NSButton) {
        closeAfterExplicitSave()
        onShowNotes()
    }

    private func closeAfterExplicitSave() {
        save()
        savesOnClose = false
        close()
    }

    @objc private func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(menuItem(title: AppText.localized("导出当前笔记...", "Export This Note..."), action: #selector(exportCurrentNoteTapped(_:))))
        menu.addItem(menuItem(title: AppText.localized("复制 Markdown", "Copy Markdown"), action: #selector(copyMarkdownTapped(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: AppText.localized("删除笔记", "Delete Note"), action: #selector(deleteCurrentNoteTapped(_:))))
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4), in: sender)
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func exportCurrentNoteTapped(_ sender: NSMenuItem) {
        save()
        onExportNote(note)
    }

    @objc private func copyMarkdownTapped(_ sender: NSMenuItem) {
        save()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.markdown, forType: .string)
        statusLabel.stringValue = AppText.localized("已复制 Markdown", "Markdown copied")
    }

    @objc private func deleteCurrentNoteTapped(_ sender: NSMenuItem) {
        onDeleteNote(note)
    }

    func selectedText() -> String {
        selectedText(in: textView.selectedRange())
    }

    func selectedText(in range: NSRange) -> String {
        guard range.length > 0,
              let valueRange = Range(range, in: textView.string) else {
            return ""
        }
        return String(textView.string[valueRange])
    }

    func updateAIToolbarPosition() {
        positionFloatingView(aiToolbarContainer)
    }

    func positionAskInputNearSelection() {
        positionFloatingView(askInputContainer)
    }

    private func positionFloatingView(_ floatingView: NSView) {
        guard let root = window?.contentView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView else { return }
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        selectionRect.origin.x += textView.textContainerOrigin.x
        selectionRect.origin.y += textView.textContainerOrigin.y
        let rectInScrollView = textView.convert(selectionRect, to: scrollView)
        let rectInRoot = scrollView.convert(rectInScrollView, to: root)
        let allowedRect = scrollView.convert(scrollView.bounds, to: root)
            .insetBy(dx: Metrics.floatingToolbarInset, dy: Metrics.floatingToolbarInset)
        let toolbarSize = floatingView.frame.size
        let minX = allowedRect.minX
        let maxX = max(minX, allowedRect.maxX - toolbarSize.width)
        let x = clamped(rectInRoot.midX - toolbarSize.width / 2, min: minX, max: maxX)
        let belowY = rectInRoot.minY - toolbarSize.height - 8
        let aboveY = rectInRoot.maxY + 8
        let minY = allowedRect.minY
        let maxY = max(minY, allowedRect.maxY - toolbarSize.height)
        let y = floatingToolbarY(belowSelection: belowY, aboveSelection: aboveY, minY: minY, maxY: maxY)
        floatingView.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func floatingToolbarY(belowSelection: CGFloat, aboveSelection: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGFloat {
        if belowSelection >= minY {
            return min(belowSelection, maxY)
        }
        if aboveSelection <= maxY {
            return max(aboveSelection, minY)
        }
        return clamped(belowSelection, min: minY, max: maxY)
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

}
