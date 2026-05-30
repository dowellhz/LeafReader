import AVFoundation
import Cocoa

final class ChatInputTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            copySelectionToClipboard()
            return true
        case "x":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            copySelectionToClipboard()
            currentEditor()?.delete(nil)
            return true
        case "v":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            pasteFromClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func copySelectionToClipboard() {
        currentEditor()?.copySelectionToClipboard()
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.pasteStringFromClipboard(transform: normalizedSingleLinePasteText)
        } else {
            stringValue += normalizedSingleLinePasteText(text)
        }
    }

    private func normalizedSingleLinePasteText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

final class ChatBubbleTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        (delegate as? AIChatPanel)?.beginBubbleTextSelection(self)
        super.mouseDown(with: event)
        (delegate as? AIChatPanel)?.finishBubbleTextSelection(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)),
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return super.performKeyEquivalent(with: event)
        }
        return copySelectionToClipboard() || super.performKeyEquivalent(with: event)
    }

    func copySelectionToClipboard() -> Bool {
        currentEditor()?.copySelectionToClipboard() ?? false
    }

    func clearTextSelection() {
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        window?.makeFirstResponder(nil)
    }

    var selectedTextValue: String {
        guard let editor = currentEditor() else { return "" }
        return editor.selectedString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var selectedTextRange: NSRange? {
        guard let editor = currentEditor() else { return nil }
        let range = editor.selectedRange
        return range.length > 0 ? range : nil
    }
}

final class WordSpeakerButton: NSButton {
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

final class BubbleDeleteButton: NSButton {
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

final class AIChatPanel: NSView, NSTextFieldDelegate {
    static let readerBodyFontSize: CGFloat = 15
    static let bubbleBodyFontSize: CGFloat = 17
    static let maxSavedConversationBubbles = 100
    static let maxContextMessages = 40
    static let maxVisibleNormalConversationBubbles = 120
    static let maxInitialLinkedWordBubbles = 30
    static let maxInitialSavedConversationBubbles = 40

    let client = AIClient()
    let dictionaryLookupService: DictionaryLookupService = LocalDictionaryLookupService.shared
    lazy var llmAnswerProvider: StreamingAnswerProvider = LLMAnswerProvider(client: client)
    let askButton = GradientButton(title: "", target: nil, action: nil)
    let summaryButton = CapsuleChromeButton(title: "", target: nil, action: nil)
    let translateButton = CapsuleChromeButton(title: "", target: nil, action: nil)
    let scrollView = NSScrollView()
    let transcriptStack = FlippedStackView()
    let statusRow = NSView()
    let statusLabel = NSTextField(labelWithString: "")
    let cancelRequestButton = NSButton(title: "", target: nil, action: nil)
    let inputBar = NSView()
    let inputField = ChatInputTextField(string: "")
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let loadingDots = LoadingDotsView()
    let speechSynthesizer = AVSpeechSynthesizer()
    let requestState = AIRequestState()
    var lastFailedAIRequest: FailedAIRequest?

    var onAskSelectedText: ((String) -> String?)?
    var onSelectedWordQuestionStarted: ((String) -> String?)?
    var onLinkedWordAnswerAvailable: ((String) -> String?)?
    var onLinkedAnswerCompleted: ((String, String, String) -> Void)?
    var onLinkedAnswerFailed: ((String) -> Void)?
    var onLinkedBubbleSelected: ((String) -> Void)?
    var onLinkedBubbleDeleted: ((String) -> Void)?
    var onSummarizeCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onTranslateCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onCurrentReadingContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onDocumentQuestionPrompt: DocumentQuestionPromptHandler?
    var onDocumentQuestionCancelled: (() -> Void)?
    var onSettingsRequired: (() -> Void)?
    var onConversationChanged: ((SavedAIConversation) -> Void)?
    var onConversationBubblesDeleted: (([SavedAIConversationBubble]) -> Void)?
    var onConversationSourcesChanged: (([AIConversationSourceLocation]) -> Void)?
    var onCurrentSourceLocation: (() -> AIConversationSourceLocation?)?
    var onConversationBubbleSelected: ((AIConversationSourceLocation) -> Void)?
    var onNonFollowUpSelectionInteraction: (() -> Void)?
    var lastNotifiedConversationSources: [AIConversationSourceLocation] = []

    var selectedText = ""
    var transcriptEntries: [TranscriptEntry] = []
    var messages: [ChatMessage] = [
        ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
    ]
    var isBusy = false
    var pendingStreamText = ""
    var lastStreamUpdateAt = Date.distantPast
    var isEditingFollowUp = false
    var ignoreEmptySelectionUntil = Date.distantPast
    var localMouseMonitor: Any?
    weak var activeBubbleTextField: ChatBubbleTextField?
    var activeBubbleSelectionRange: NSRange?
    var activeBubbleSelectedText = ""
    var streamUpdateWorkItem: DispatchWorkItem?
    var transcriptLayoutWorkItem: DispatchWorkItem?
    weak var pendingTranscriptScrollTarget: NSView?
    var pendingTranscriptForceScroll = false
    var readerTheme: ReaderTheme = .original
    var isDarkMode = false
    var bubbleMetadataByID: [String: BubbleMetadata] = [:]
    var bubbleBoxByLinkID: [String: ChatBubbleView] = [:]
    var persistentBubbleIDs: [String] = []
    var isLoadingLinkedWordBubbles = false
    var isRestoringSavedConversation = false
    var selectedLinkID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        installInteractionMonitor()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        streamUpdateWorkItem?.cancel()
        transcriptLayoutWorkItem?.cancel()
        requestState.cancelTasks()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContentVisible(_ visible: Bool) {
        subviews.forEach { $0.isHidden = !visible }
        layer?.backgroundColor = visible
            ? panelBackgroundColor.cgColor
            : NSColor.clear.cgColor
        needsLayout = true
    }

    func setDarkMode(_ enabled: Bool) {
        setTheme(enabled ? .dark : .original)
    }

    func setTheme(_ theme: ReaderTheme) {
        readerTheme = theme
        isDarkMode = theme == .dark
        layer?.backgroundColor = panelBackgroundColor.cgColor
        statusLabel.textColor = secondaryTextColor
        inputBar.layer?.backgroundColor = inputBackgroundColor.cgColor
        inputBar.layer?.borderWidth = theme == .original ? 0 : 1
        inputBar.layer?.borderColor = inputBorderColor.cgColor
        inputField.textColor = primaryTextColor
        askButton.theme = theme
        askButton.layer?.shadowColor = aiAccentColor.cgColor
        summaryButton.theme = theme
        translateButton.theme = theme
        loadingDots.accentColor = aiAccentColor
        sendButton.contentTintColor = sendButtonTintColor
        cancelRequestButton.contentTintColor = secondaryTextColor
        restyleTranscript()
    }
}
