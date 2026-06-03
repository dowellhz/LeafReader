import Cocoa

final class ReadingNotePanelController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    typealias Metrics = ReadingNotePanelMetrics

    struct AskRequest {
        let question: String
        let selectedText: String
    }

    let textView = ReadingNoteTextView()
    let aiRunner = AITextActionRunner()
    let aiToolbarContainer = NSView()
    let aiToolbar = NSStackView()
    let explainButton = NSButton(title: AppText.localized("解析", "Explain"), target: nil, action: nil)
    let translateButton = NSButton(title: AppText.localized("翻译", "Translate"), target: nil, action: nil)
    let summarizeButton = NSButton(title: AppText.localized("总结", "Summarize"), target: nil, action: nil)
    let polishButton = NSButton(title: AppText.localized("整理", "Organize"), target: nil, action: nil)
    let difficultSentenceButton = NSButton(title: AppText.localized("难句", "Syntax"), target: nil, action: nil)
    let askButton = NSButton(title: AppText.localized("问 AI", "Ask AI"), target: nil, action: nil)
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
        [explainButton, translateButton, summarizeButton, polishButton, difficultSentenceButton, askButton]
    }
    let editorState = ReadingNoteEditorState()
    weak var scrollView: NSScrollView?
    var isAskInputVisible: Bool {
        !askInputContainer.isHidden
    }
    var note: ReadingNote
    let onSave: (ReadingNote) -> Void
    private let onClose: (String) -> Void
    let onShowNotes: () -> Void
    let onExportNote: (ReadingNote) -> Void
    let onDeleteNote: (ReadingNote) -> Void
    let onDocumentQuestionPrompt: DocumentQuestionPromptHandler?
    let onModelSettingsRequired: () -> Void

    init(
        note: ReadingNote,
        onSave: @escaping (ReadingNote) -> Void,
        onClose: @escaping (String) -> Void,
        onShowNotes: @escaping () -> Void,
        onExportNote: @escaping (ReadingNote) -> Void,
        onDeleteNote: @escaping (ReadingNote) -> Void,
        onDocumentQuestionPrompt: DocumentQuestionPromptHandler? = nil,
        onModelSettingsRequired: @escaping () -> Void = {}
    ) {
        self.note = note
        self.onSave = onSave
        self.onClose = onClose
        self.onShowNotes = onShowNotes
        self.onExportNote = onExportNote
        self.onDeleteNote = onDeleteNote
        self.onDocumentQuestionPrompt = onDocumentQuestionPrompt
        self.onModelSettingsRequired = onModelSettingsRequired
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.initialPanelSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("阅读笔记", "Reading Note")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = Metrics.minimumPanelSize
        super.init(window: panel)
        panel.delegate = self
        buildContent(in: panel)
        applyTheme(ReaderTheme.selected)
        renderMarkdownIntoEditor(note.markdown)
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
        if let askInputKeyMonitor = editorState.askInputKeyMonitor {
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
        editorState.isClosing = true
        editorState.cancelAIRequests()
        aiRunner.cancel()
        if let window {
            window.parent?.removeChildWindow(window)
        }
        editorState.cancelAutoSave()
        if editorState.savesOnClose {
            save()
        }
        onClose(note.id)
    }

    func refreshTheme() {
        applyTheme(ReaderTheme.selected)
        renderMarkdownIntoEditor(markdownFromEditor())
    }

    func textDidChange(_ notification: Notification) {
        scheduleAutoSave()
        refreshEditorDerivedState()
    }

    func closeWithoutSaving() {
        editorState.cancelAutoSave()
        editorState.savesOnClose = false
        close()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshAIToolbar()
    }

    @objc func scrollBoundsDidChange(_ notification: Notification) {
        refreshAIToolbar()
    }

    @objc private func readerThemeDidChange(_ notification: Notification) {
        refreshTheme()
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
