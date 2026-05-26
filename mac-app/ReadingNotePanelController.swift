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

    private struct AskRequest {
        let question: String
        let selectedText: String
    }

    private let textView = ReadingNoteTextView()
    private let aiRunner = AITextActionRunner()
    private let aiToolbarContainer = NSView()
    private let aiToolbar = NSStackView()
    private let explainButton = NSButton(title: AppText.localized("解析", "Explain"), target: nil, action: nil)
    private let translateButton = NSButton(title: AppText.localized("翻译", "Translate"), target: nil, action: nil)
    private let summarizeButton = NSButton(title: AppText.localized("总结", "Summarize"), target: nil, action: nil)
    private let polishButton = NSButton(title: AppText.localized("润色", "Polish"), target: nil, action: nil)
    private let askButton = NSButton(title: AppText.localized("问 AI", "Ask AI"), target: nil, action: nil)
    private let askInputContainer = NSView()
    private let askInputField = ReadingNoteAskTextField(string: "")
    private let askSendButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let rootView = NSView()
    private let titleIconView = NSImageView()
    private let metadataView = NSView()
    private let editorContainer = NSView()
    private var topIconButtons: [NSButton] = []
    private var aiActionButtons: [NSButton] {
        [explainButton, translateButton, summarizeButton, polishButton, askButton]
    }
    private var pendingAskSelectedText = ""
    private var aiPlaceholderDisplayText: String?
    private weak var scrollView: NSScrollView?
    private var note: ReadingNote
    private let onSave: (ReadingNote) -> Void
    private let onClose: (String) -> Void
    private let onShowNotes: () -> Void
    private let onExportNote: (ReadingNote) -> Void
    private let onDeleteNote: (ReadingNote) -> Void
    private let onDocumentQuestionPrompt: ((String, String, @escaping (String?) -> Void) -> Void)?
    private var savesOnClose = true
    private var autoSaveWorkItem: DispatchWorkItem?

    init(
        note: ReadingNote,
        onSave: @escaping (ReadingNote) -> Void,
        onClose: @escaping (String) -> Void,
        onShowNotes: @escaping () -> Void,
        onExportNote: @escaping (ReadingNote) -> Void,
        onDeleteNote: @escaping (ReadingNote) -> Void,
        onDocumentQuestionPrompt: ((String, String, @escaping (String?) -> Void) -> Void)? = nil
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
        refreshAIToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
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
        titleIconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
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
            symbol: "ellipsis",
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
        askInputContainer.isHidden = true
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

    private func applyTheme(_ theme: ReaderTheme) {
        let background = ReadingNoteTheme.panelBackground(theme)
        let text = ReadingNoteTheme.primaryText(theme)
        window?.backgroundColor = background
        window?.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        rootView.layer?.backgroundColor = background.cgColor
        rootView.layer?.cornerRadius = 18
        metadataView.layer?.backgroundColor = ReadingNoteTheme.insetBackground(theme).cgColor
        metadataView.layer?.cornerRadius = 8
        editorContainer.layer?.backgroundColor = ReadingNoteTheme.editorBackground(theme).cgColor
        editorContainer.layer?.cornerRadius = 9
        editorContainer.layer?.borderWidth = 1
        editorContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        textView.backgroundColor = ReadingNoteTheme.editorBackground(theme)
        textView.textColor = text
        textView.insertionPointColor = text
        textView.font = NSFont.systemFont(ofSize: 15)
        titleIconView.contentTintColor = text
        applyTextColor(text, in: rootView)
        applyControlTint(text, in: rootView)
        applyTopIconButtonTheme(theme)
        statusLabel.textColor = text.withAlphaComponent(0.72)
        wordCountLabel.textColor = text.withAlphaComponent(0.58)
        aiToolbarContainer.layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        aiToolbarContainer.layer?.borderWidth = 1
        aiToolbarContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        askInputContainer.layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        askInputContainer.layer?.borderWidth = 1
        askInputContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        askInputField.textColor = text
        askSendButton.contentTintColor = text
        aiActionButtons.forEach {
            $0.layer?.backgroundColor = NSColor.clear.cgColor
            $0.contentTintColor = text
        }
    }

    private func applyTopIconButtonTheme(_ theme: ReaderTheme) {
        for button in topIconButtons {
            button.layer?.backgroundColor = ReadingNoteTheme.secondaryButtonBackground(theme).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        }
    }

    private func save() {
        note.markdown = markdownFromEditor()
        note.updatedAt = Date()
        onSave(note)
    }

    private func updateWordCount() {
        let count = textView.string.trimmingCharacters(in: .whitespacesAndNewlines).count
        wordCountLabel.stringValue = AppText.localized("\(count) 字", "\(count) chars")
    }

    private func renderMarkdownIntoEditor(_ markdown: String) {
        let rendered = MarkdownRenderer.render(markdown, fontSize: 15, textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected))
        textView.textStorage?.setAttributedString(rendered)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        ]
    }

    private func markdownFromEditor() -> String {
        let attributed = textView.attributedString()
        let output = NSMutableString()
        (attributed.string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: attributed.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            let line = attributed.attributedSubstring(from: range)
            output.append(self.markdownLine(from: line))
            output.append("\n")
        }
        return (output as String).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func markdownLine(from attributed: NSAttributedString) -> String {
        if let imageMarkdown = imageMarkdownLine(from: attributed) {
            return imageMarkdown
        }
        let rawLine = attributed.string.trimmingCharacters(in: .newlines)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("• ") {
            return "- " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☐ ") {
            return "- [ ] " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☑ ") {
            return "- [x] " + String(trimmed.dropFirst(2))
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        if let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            if font.pointSize >= 18 {
                return "# " + trimmed
            }
            if font.fontDescriptor.symbolicTraits.contains(.bold), isEntireRange(attributed, matching: .bold) {
                return "**" + trimmed + "**"
            }
        }
        return inlineMarkdown(from: attributed, range: fullRange)
    }

    private func imageMarkdownLine(from attributed: NSAttributedString) -> String? {
        var value: String?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, stop in
            guard attributes[.attachment] is NSTextAttachment else { return }
            let urlString = (attributes[.link] as? String) ?? (attributes[.link] as? URL)?.absoluteString
            guard let urlString,
                  let url = URL(string: urlString) else { return }
            let name = url.deletingPathExtension().lastPathComponent
            value = "![\(name)](\(url.path))"
            stop.pointee = true
        }
        return value
    }

    private func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        var output = ""
        attributed.enumerateAttributes(in: range) { attributes, subrange, _ in
            let text = attributed.attributedSubstring(from: subrange).string
            guard !text.isEmpty else { return }
            guard let font = attributes[.font] as? NSFont else {
                output += text
                return
            }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                output += "**\(text)**"
            } else if traits.contains(.italic) {
                output += "*\(text)*"
            } else {
                output += text
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private func isEntireRange(_ attributed: NSAttributedString, matching trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        var matches = true
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let font = value as? NSFont,
                  font.fontDescriptor.symbolicTraits.contains(trait) else {
                matches = false
                stop.pointee = true
                return
            }
        }
        return matches
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

    private func applyTextColor(_ color: NSColor, in view: NSView) {
        for subview in view.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.textColor = color.withAlphaComponent(label === wordCountLabel ? 0.58 : 1)
            }
            applyTextColor(color, in: subview)
        }
    }

    private func applyControlTint(_ color: NSColor, in view: NSView) {
        for subview in view.subviews {
            if let button = subview as? NSButton {
                button.contentTintColor = color
            }
            applyControlTint(color, in: subview)
        }
    }

    private func scheduleAutoSave() {
        autoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        autoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func refreshAIToolbar() {
        let enabled = !aiRunner.isRunning
        aiActionButtons.forEach { $0.isEnabled = enabled }
        if !askInputContainer.isHidden {
            positionAskInputNearSelection()
            return
        }
        guard !aiRunner.isRunning, selectedText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            aiToolbarContainer.isHidden = true
            return
        }
        updateAIToolbarPosition()
        aiToolbarContainer.isHidden = false
    }

    @objc private func scrollBoundsDidChange(_ notification: Notification) {
        refreshAIToolbar()
    }

    @objc private func readerThemeDidChange(_ notification: Notification) {
        refreshTheme()
    }

    @objc private func explainSelection(_ sender: NSButton) {
        runAIAction(.explain, title: AppText.localized("解析", "Explain"))
    }

    @objc private func translateSelection(_ sender: NSButton) {
        runAIAction(.translate, title: AppText.localized("翻译", "Translate"))
    }

    @objc private func summarizeSelection(_ sender: NSButton) {
        runAIAction(.summarize, title: AppText.localized("总结", "Summarize"))
    }

    @objc private func polishSelection(_ sender: NSButton) {
        runAIAction(.polish, title: AppText.localized("润色", "Polish"), replaceSelection: true)
    }

    @objc private func showAskInput(_ sender: NSButton) {
        let selected = selectedText()
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        pendingAskSelectedText = selected
        askInputField.stringValue = ""
        aiToolbarContainer.isHidden = true
        positionAskInputNearSelection()
        askInputContainer.isHidden = false
        window?.makeFirstResponder(askInputField)
    }

    @objc private func submitAskQuestion(_ sender: Any?) {
        let question = askInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = makeAskRequest(question: question) else { return }
        runAskQuestion(request)
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

    @objc private func undoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canUndo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.undo()
        save()
        updateWordCount()
    }

    @objc private func redoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canRedo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.redo()
        save()
        updateWordCount()
    }

    @objc private func boldTapped(_ sender: NSButton) {
        wrapSelection(prefix: "**", suffix: "**")
    }

    @objc private func italicTapped(_ sender: NSButton) {
        wrapSelection(prefix: "*", suffix: "*")
    }

    @objc private func listTapped(_ sender: NSButton) {
        applyLinePrefix(displayPrefix: "• ")
    }

    @objc private func checklistTapped(_ sender: NSButton) {
        applyLinePrefix(displayPrefix: "☐ ")
    }

    @objc private func imageTapped(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .webP, .heic]
        panel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.insertImage(url: url)
        }
    }

    private func runSlashContinuation() {
        let prefix = textBeforeCursor().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return }
        runAIAction(.continueLine, title: AppText.localized("补充", "Continue"), sourceText: prefix, replaceSlashLine: true)
    }

    private func runAIAction(
        _ action: AITextActionRunner.Action,
        title: String,
        sourceText: String? = nil,
        replaceSlashLine: Bool = false,
        replaceSelection: Bool = false
    ) {
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            statusLabel.stringValue = AppText.localized("请先配置 API Key", "Configure API Key first")
            NSSound.beep()
            return
        }
        let selectionRange = textView.selectedRange()
        let text = sourceText ?? selectedText(in: selectionRange)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLabel.stringValue = AppText.localized("请先选中笔记中的文字", "Select text in the note first")
            NSSound.beep()
            return
        }
        setRunning(true, title: title)
        aiToolbarContainer.isHidden = true
        let usesTailPlaceholder = !replaceSlashLine && !replaceSelection
        if usesTailPlaceholder {
            appendAIPlaceholder(title: title)
        }
        aiRunner.run(action: action, text: text, noteContext: textView.string) { [weak self] result in
            guard let self else { return }
            self.setRunning(false, title: "")
            switch result {
            case .success(let output):
                let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                if replaceSlashLine {
                    self.replaceCurrentSlashLine(with: value)
                } else if replaceSelection {
                    self.replaceSelectedText(in: selectionRange, with: value)
                } else if usesTailPlaceholder {
                    self.replaceAIPlaceholder(title: title, body: value)
                } else {
                    self.appendAISection(title: title, body: value)
                }
            case .failure(let error):
                if usesTailPlaceholder {
                    self.removeAIPlaceholder()
                }
                self.statusLabel.stringValue = self.userFacingError(error)
            }
        }
    }

    private func makeAskRequest(question: String) -> AskRequest? {
        guard !question.isEmpty else {
            NSSound.beep()
            return nil
        }
        let selected = pendingAskSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            statusLabel.stringValue = AppText.localized("请先选中笔记中的文字", "Select text in the note first")
            NSSound.beep()
            return nil
        }
        return AskRequest(question: question, selectedText: selected)
    }

    private func runAskQuestion(_ request: AskRequest) {
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            statusLabel.stringValue = AppText.localized("请先配置 API Key", "Configure API Key first")
            NSSound.beep()
            return
        }
        askInputContainer.isHidden = true
        askInputField.stringValue = ""
        window?.makeFirstResponder(textView)
        setRunning(true, title: AppText.localized("问 AI", "Ask AI"))
        let context = askDocumentContext(selectedText: request.selectedText)
        appendAIPlaceholder(title: request.question)
        if let onDocumentQuestionPrompt {
            onDocumentQuestionPrompt(request.question, context) { [weak self] prompt in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.runAskPrompt(prompt, request: request)
                    } else {
                        self.runAskFallback(request)
                    }
                }
            }
            return
        }
        runAskFallback(request)
    }

    private func runAskPrompt(_ prompt: String, request: AskRequest) {
        aiRunner.runPrompt(prompt) { [weak self] result in
            self?.finishAskQuestion(result, request: request)
        }
    }

    private func runAskFallback(_ request: AskRequest) {
        aiRunner.runQuestion(question: request.question, selectedText: request.selectedText) { [weak self] result in
            self?.finishAskQuestion(result, request: request)
        }
    }

    private func finishAskQuestion(_ result: Result<String, Error>, request: AskRequest) {
        setRunning(false, title: "")
        switch result {
        case .success(let output):
            let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            replaceAIPlaceholder(title: request.question, body: value)
            pendingAskSelectedText = ""
        case .failure(let error):
            removeAIPlaceholder()
            statusLabel.stringValue = userFacingError(error)
        }
    }

    private func askDocumentContext(selectedText: String) -> String {
        if AppText.isChinese {
            return """
            【阅读笔记选中内容】
            \(selectedText)

            【当前阅读笔记】
            \(ReaderAIContextPolicy.prefix(markdownFromEditor(), limit: 2000))
            """
        }
        return """
        [Selected reading-note text]
        \(selectedText)

        [Current reading note]
        \(ReaderAIContextPolicy.prefix(markdownFromEditor(), limit: 2000))
        """
    }

    private func setRunning(_ running: Bool, title: String) {
        statusLabel.stringValue = running ? AppText.localized("\(title)中...", "\(title)...") : ""
        refreshAIToolbar()
    }

    private func appendAISection(title: String, body: String) {
        let suffix = markdownFromEditor().hasSuffix("\n") ? "" : "\n"
        renderMarkdownIntoEditor(markdownFromEditor() + "\(suffix)\n### \(title)\n\n\(body)\n")
        textView.scrollToEndOfDocument(nil)
        save()
    }

    private func appendAIPlaceholder(title: String) {
        let placeholderText = AppText.localized(" 正在生成...", " Generating...")
        let suffix = markdownFromEditor().hasSuffix("\n") ? "" : "\n"
        let rendered = NSMutableAttributedString(attributedString: MarkdownRenderer.render(
            markdownFromEditor() + "\(suffix)\n### \(title)\n\n",
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        ))
        rendered.append(aiPlaceholderAttributedString(text: placeholderText))
        rendered.append(NSAttributedString(string: "\n"))
        textView.textStorage?.setAttributedString(rendered)
        aiPlaceholderDisplayText = "\(title)\n\n\u{fffc}\(placeholderText)"
        textView.scrollToEndOfDocument(nil)
    }

    private func replaceAIPlaceholder(title: String, body: String) {
        let replacement = MarkdownRenderer.render("### \(title)\n\n\(body)\n", fontSize: 15, textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected))
        guard let range = aiPlaceholderRange() else {
            appendAISection(title: title, body: body)
            return
        }
        replaceText(in: range, with: replacement)
        textView.scrollToEndOfDocument(nil)
        aiPlaceholderDisplayText = nil
    }

    private func removeAIPlaceholder() {
        guard let range = aiPlaceholderRange() else {
            aiPlaceholderDisplayText = nil
            return
        }
        replaceText(in: expandedPlaceholderRemovalRange(range), with: "")
        aiPlaceholderDisplayText = nil
    }

    private func aiPlaceholderRange() -> NSRange? {
        guard let display = aiPlaceholderDisplayText else { return nil }
        let range = (textView.string as NSString).range(of: display)
        return range.location == NSNotFound ? nil : range
    }

    private func expandedPlaceholderRemovalRange(_ range: NSRange) -> NSRange {
        let nsText = textView.string as NSString
        var location = range.location
        var length = range.length
        while location > 0, nsText.substring(with: NSRange(location: location - 1, length: 1)) == "\n" {
            location -= 1
            length += 1
        }
        while location + length < nsText.length,
              nsText.substring(with: NSRange(location: location + length, length: 1)) == "\n" {
            length += 1
        }
        return NSRange(location: location, length: length)
    }

    private func aiPlaceholderAttributedString(text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        attachment.image = symbol
        attachment.bounds = NSRect(x: 0, y: -2, width: 15, height: 15)
        output.append(NSAttributedString(attachment: attachment))
        output.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: ReadingNoteTheme.secondaryText(ReaderTheme.selected)
            ]
        ))
        return output
    }

    private func selectedText() -> String {
        selectedText(in: textView.selectedRange())
    }

    private func selectedText(in range: NSRange) -> String {
        guard range.length > 0,
              let valueRange = Range(range, in: textView.string) else {
            return ""
        }
        return String(textView.string[valueRange])
    }

    private func updateAIToolbarPosition() {
        positionFloatingView(aiToolbarContainer)
    }

    private func positionAskInputNearSelection() {
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

    private func textBeforeCursor() -> String {
        let location = textView.selectedRange().location
        guard location <= (textView.string as NSString).length else { return textView.string }
        return (textView.string as NSString).substring(to: location)
    }

    private func replaceCurrentSlashLine(with value: String) {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let replacement = value + "\n"
        replaceText(in: lineRange, with: replacement)
    }

    private func replaceSelectedText(in range: NSRange, with value: String) {
        guard range.length > 0 else { return }
        replaceText(in: boundedSelectionRange(location: range.location, length: range.length), with: value)
    }

    private func wrapSelection(prefix: String, suffix: String) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            NSSound.beep()
            return
        }
        guard let selected = textView.textStorage?.attributedSubstring(from: range).mutableCopy() as? NSMutableAttributedString else { return }
        let font: NSFont = prefix == "**"
            ? NSFont.boldSystemFont(ofSize: 15)
            : NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask)
        selected.addAttribute(.font, value: font, range: NSRange(location: 0, length: selected.length))
        replaceText(in: range, with: selected)
        textView.setSelectedRange(NSRange(location: range.location, length: selected.length))
    }

    private func applyLinePrefix(displayPrefix: String) {
        let selection = textView.selectedRange()
        guard selection.length > 0 else {
            insertListPrefixAtInsertionPoint(displayPrefix)
            return
        }
        let nsText = textView.string as NSString
        let paragraphRange = nsText.paragraphRange(for: selection)
        let selected = nsText.substring(with: paragraphRange) as NSString
        let shouldRemovePrefix = selectionAlreadyUsesPrefix(displayPrefix, in: selected)
        var offset = 0
        let replacement = NSMutableString()
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, enclosingRange, _ in
            let line = selected.substring(with: lineRange)
            let enclosing = selected.substring(with: enclosingRange)
            let newlineSuffix = String(enclosing.dropFirst(line.count))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                replacement.append(line + newlineSuffix)
            } else if shouldRemovePrefix {
                let updated = self.removingLinePrefix(displayPrefix, from: line)
                replacement.append(updated + newlineSuffix)
                offset -= line.count - updated.count
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("☐ ") || trimmed.hasPrefix("☑ ") {
                replacement.append(line + newlineSuffix)
            } else {
                replacement.append(displayPrefix + line + newlineSuffix)
                offset += displayPrefix.count
            }
        }
        let oldLocation = selection.location
        let oldEnd = selection.location + selection.length
        replaceText(in: paragraphRange, with: replacement as String)
        let newLocation = oldLocation + (oldLocation == paragraphRange.location ? 0 : displayPrefix.count)
        let newLength = max(0, oldEnd - oldLocation + offset)
        textView.setSelectedRange(boundedSelectionRange(location: newLocation, length: newLength))
    }

    private func selectionAlreadyUsesPrefix(_ displayPrefix: String, in selected: NSString) -> Bool {
        selectedNonEmptyLines(in: selected).allSatisfy { lineHasPrefix(displayPrefix, $0) }
    }

    private func selectedNonEmptyLines(in selected: NSString) -> [String] {
        var lines: [String] = []
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = selected.substring(with: lineRange)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    private func lineHasPrefix(_ displayPrefix: String, _ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(displayPrefix)
    }

    private func removingLinePrefix(_ displayPrefix: String, from line: String) -> String {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let remainder = line.dropFirst(leadingWhitespace.count)
        guard remainder.hasPrefix(displayPrefix) else { return line }
        return String(leadingWhitespace) + String(remainder.dropFirst(displayPrefix.count))
    }

    private func boundedSelectionRange(location: Int, length: Int) -> NSRange {
        let textLength = (textView.string as NSString).length
        let boundedLocation = min(max(0, location), textLength)
        let boundedLength = min(max(0, length), textLength - boundedLocation)
        return NSRange(location: boundedLocation, length: boundedLength)
    }

    private func insertListPrefixAtInsertionPoint(_ displayPrefix: String) {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        let insertPrefix = location == 0 || nsText.substring(to: location).hasSuffix("\n") ? "" : "\n"
        insertTextAtSelection(insertPrefix + displayPrefix)
    }

    private func insertTextAtSelection(_ value: String) {
        let range = textView.selectedRange()
        replaceText(in: range, with: value)
    }

    private func insertImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            NSSound.beep()
            return
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = scaledImageBounds(for: image)
        let value = NSMutableAttributedString(attachment: attachment)
        value.addAttribute(.link, value: url.absoluteString, range: NSRange(location: 0, length: value.length))
        value.append(NSAttributedString(string: "\n"))
        let range = textView.selectedRange()
        replaceText(in: range, with: value)
    }

    private func replaceText(in range: NSRange, with value: String) {
        guard textView.shouldChangeText(in: range, replacementString: value) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (value as NSString).length, length: 0))
        save()
        updateWordCount()
    }

    private func replaceText(in range: NSRange, with value: NSAttributedString) {
        guard textView.shouldChangeText(in: range, replacementString: value.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + value.length, length: 0))
        save()
        updateWordCount()
    }

    private func scaledImageBounds(for image: NSImage) -> NSRect {
        let maxWidth: CGFloat = 360
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: -4, width: 180, height: 120)
        }
        let scale = min(1, maxWidth / size.width)
        return NSRect(x: 0, y: -4, width: size.width * scale, height: size.height * scale)
    }

    private func userFacingError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == -10 {
            return AppText.localized("请先配置 API Key", "Configure API Key first")
        }
        if nsError.domain == NSURLErrorDomain {
            return AppText.localized("AI 请求失败，请检查网络", "AI request failed. Check the network.")
        }
        return AppText.localized("AI 请求失败", "AI request failed")
    }
}

final class ReadingNoteTextView: NSTextView {
    var onSelectionChanged: (() -> Void)?
    var onSlashCommand: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        onSelectionChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, currentLineIsSlashCommand() {
            onSlashCommand?()
            return
        }
        super.keyDown(with: event)
    }

    private func currentLineIsSlashCommand() -> Bool {
        let nsText = string as NSString
        let location = min(selectedRange().location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return line == "/"
    }
}

final class ReadingNoteAskTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        case "v":
            currentEditor()?.paste(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

final class ReadingNoteIconButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}
