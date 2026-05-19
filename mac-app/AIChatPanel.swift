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
        guard let editor = currentEditor() else { return }
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let singleLineText = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: singleLineText)
        } else {
            stringValue += singleLineText
        }
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
        guard let editor = currentEditor() else { return false }
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
        return true
    }

    func clearTextSelection() {
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        window?.makeFirstResponder(nil)
    }

    var selectedTextValue: String {
        guard let editor = currentEditor() else { return "" }
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return ""
        }
        return String(editor.string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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
    static let maxSavedConversationBubbles = 100
    static let maxContextMessages = 40
    static let maxVisibleNormalConversationBubbles = 120
    static let maxInitialLinkedWordBubbles = 30
    static let maxInitialSavedConversationBubbles = 40

    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }

    let client = AIClient()
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
    var currentStreamTask: Task<Void, Never>?
    var currentDataTask: URLSessionDataTask?
    var activeRequestID: UUID?
    var cancelledRequestIDs = Set<UUID>()
    weak var activeAssistantBody: NSTextField?
    var lastFailedAIRequest: FailedAIRequest?

    struct BubbleMetadata {
        var role: String
        var text: String
        var renderMarkdown: Bool
        var collapsible: Bool
        var linkID: String?
        var sourceLocation: AIConversationSourceLocation?
    }

    struct FailedAIRequest {
        let messages: [ChatMessage]
        let linkID: String?
        let linkedQuestion: String?
    }

    var onAskSelectedText: ((String) -> String?)?
    var onSelectedWordQuestionStarted: ((String) -> String?)?
    var onLinkedWordAnswerAvailable: ((String) -> String?)?
    var onLinkedAnswerCompleted: ((String, String, String) -> Void)?
    var onLinkedAnswerFailed: ((String) -> Void)?
    var onLinkedBubbleSelected: ((String) -> Void)?
    var onSummarizeCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onTranslateCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onCurrentReadingContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onDocumentQuestionPrompt: ((String, String, @escaping (String?) -> Void) -> Void)?
    var onSettingsRequired: (() -> Void)?
    var onConversationChanged: ((SavedAIConversation) -> Void)?
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
        currentStreamTask?.cancel()
        currentDataTask?.cancel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedText(_ text: String) {
        if shouldIgnoreEmptySelectionUpdate(text) {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clearActiveBubbleSelection(restoreRendering: true, clearSelectedTextState: false)
        }
        updateSelectedText(trimmed)
    }

    func clearSelectedText() {
        clearActiveBubbleSelection(restoreRendering: true, clearSelectedTextState: false)
        updateSelectedText("")
    }

    func setSelectedBubbleText(_ text: String) {
        updateSelectedText(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateSelectedText(_ text: String) {
        selectedText = text
        askButton.previewText = text
        askButton.isEnabled = !text.isEmpty
    }

    func beginBubbleTextSelection(_ bubble: ChatBubbleTextField) {
        if let previous = activeBubbleTextField, previous !== bubble {
            clearActiveBubbleSelection(restoreRendering: true, clearSelectedTextState: false)
        }
        activeBubbleSelectionRange = nil
        activeBubbleSelectedText = ""
        activeBubbleTextField = bubble
        updateSelectedText("")
        onNonFollowUpSelectionInteraction?()
    }

    func finishBubbleTextSelection(_ bubble: ChatBubbleTextField) {
        captureBubbleSelection(from: bubble)
    }

    @discardableResult
    func captureBubbleSelection(from bubble: ChatBubbleTextField) -> Bool {
        let selected = bubble.selectedTextValue
        guard !selected.isEmpty else { return false }
        activeBubbleSelectionRange = bubble.selectedTextRange
        activeBubbleSelectedText = selected
        activeBubbleTextField = bubble
        setSelectedBubbleText(selected)
        return true
    }

    func shouldIgnoreEmptySelectionUpdate(_ text: String) -> Bool {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if isEditingFollowUp || isBusy || Date() < ignoreEmptySelectionUntil {
            return true
        }
        if let responder = window?.firstResponder {
            if let view = responder as? NSView, view.isDescendant(of: self) {
                return true
            }
            if responder === inputField.currentEditor() {
                return true
            }
        }
        return false
    }

    func setContentVisible(_ visible: Bool) {
        subviews.forEach { $0.isHidden = !visible }
        layer?.backgroundColor = visible
            ? panelBackgroundColor.cgColor
            : NSColor.clear.cgColor
        needsLayout = true
    }

    func setDarkMode(_ enabled: Bool) {
        isDarkMode = enabled
        layer?.backgroundColor = panelBackgroundColor.cgColor
        statusLabel.textColor = secondaryTextColor
        inputBar.layer?.backgroundColor = inputBackgroundColor.cgColor
        inputBar.layer?.borderWidth = enabled ? 1 : 0
        inputBar.layer?.borderColor = NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1).cgColor
        inputField.textColor = primaryTextColor
        summaryButton.isDark = enabled
        translateButton.isDark = enabled
        sendButton.contentTintColor = enabled
            ? NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
            : NSColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1)
        restyleTranscript()
    }
}
