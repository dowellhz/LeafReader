import AVFoundation
import Cocoa

private final class ChatInputTextField: NSTextField {
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

    private func copySelectionToClipboard() {
        guard let editor = currentEditor() else { return }
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
    }

    private func pasteFromClipboard() {
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

private final class ChatBubbleTextField: NSTextField {
    var onInteractionEnded: ((ChatBubbleTextField) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onInteractionEnded?(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)),
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return super.performKeyEquivalent(with: event)
        }
        return copySelectionToClipboard() || super.performKeyEquivalent(with: event)
    }

    private func copySelectionToClipboard() -> Bool {
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
}

private final class WordSpeakerButton: NSButton {
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
    private static let readerBodyFontSize: CGFloat = 15

    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }

    private let client = AIClient()
    private let askButton = GradientButton(title: "", target: nil, action: nil)
    private let summaryButton = CapsuleChromeButton(title: "", target: nil, action: nil)
    private let translateButton = CapsuleChromeButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let transcriptStack = FlippedStackView()
    private let statusRow = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let inputBar = NSView()
    private let inputField = ChatInputTextField(string: "")
    private let sendButton = NSButton(title: "", target: nil, action: nil)
    private let loadingDots = LoadingDotsView()
    private let speechSynthesizer = AVSpeechSynthesizer()

    private struct BubbleMetadata {
        var role: String
        var text: String
        var renderMarkdown: Bool
        var collapsible: Bool
        var linkID: String?
    }

    var onAskSelectedText: ((String) -> String?)?
    var onSelectedWordQuestionStarted: ((String) -> String?)?
    var onLinkedAnswerCompleted: ((String, String, String) -> Void)?
    var onLinkedBubbleSelected: ((String) -> Void)?
    var onSummarizeCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onTranslateCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onCurrentReadingContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onDocumentQuestionPrompt: ((String, String, @escaping (String?) -> Void) -> Void)?
    var onSettingsRequired: (() -> Void)?

    private var selectedText = ""
    private var transcriptEntries: [TranscriptEntry] = []
    private var messages: [ChatMessage] = [
        ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
    ]
    private var isBusy = false
    private var pendingStreamText = ""
    private var isEditingFollowUp = false
    private var ignoreEmptySelectionUntil = Date.distantPast
    private var localMouseMonitor: Any?
    private var streamUpdateWorkItem: DispatchWorkItem?
    private var isDarkMode = false
    private var bubbleMetadataByID: [String: BubbleMetadata] = [:]
    private var bubbleBoxByLinkID: [String: ChatBubbleView] = [:]
    private var selectedLinkID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        installInteractionMonitor()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedText(_ text: String) {
        if shouldIgnoreEmptySelectionUpdate(text) {
            return
        }
        selectedText = text
        askButton.previewText = text
        askButton.isEnabled = !text.isEmpty
    }

    func clearSelectedText() {
        selectedText = ""
        askButton.previewText = ""
        askButton.isEnabled = false
    }

    private func shouldIgnoreEmptySelectionUpdate(_ text: String) -> Bool {
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

    func loadLinkedWordBubbles(_ records: [LinkedWordBubble]) {
        transcriptStack.arrangedSubviews.forEach { view in
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bubbleMetadataByID.removeAll()
        bubbleBoxByLinkID.removeAll()
        selectedLinkID = nil
        transcriptEntries.removeAll()
        messages = [
            ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        ]

        for record in records {
            appendBubble(role: AppText.userRole, text: vocabularyBubbleTitle(for: record.word), collapsible: false, linkID: record.id)
            appendBubble(role: AppText.aiRole, text: record.answer, collapsible: false, renderMarkdown: true, linkID: record.id)
            recordTranscript(role: AppText.userRole, text: vocabularyBubbleTitle(for: record.word))
            recordTranscript(role: AppText.aiRole, text: record.answer)
            messages.append(ChatMessage(role: "user", content: record.question))
            messages.append(ChatMessage(role: "assistant", content: record.answer))
        }
    }

    func scrollToLinkedBubble(id: String) {
        guard let box = bubbleBoxByLinkID[id] else { return }
        selectedLinkID = id
        updateLinkedBubbleSelection()
        setContentVisible(true)
        DispatchQueue.main.async { [weak self, weak box] in
            guard let self, let box else { return }
            self.scrollTranscriptToTop(of: box)
        }
    }

    func appendReferenceBubbles(_ records: [LinkedWordBubble]) {
        guard !records.isEmpty else { return }
        for record in records {
            appendBubble(
                role: AppText.localized("依据", "Source"),
                text: "\(record.question)\n\(record.answer)",
                collapsible: false,
                renderMarkdown: false,
                linkID: record.id
            )
        }
    }

    func appendNotice(_ text: String) {
        appendBubble(role: AppText.localized("提示", "Note"), text: text, collapsible: false, renderMarkdown: false)
    }

    @objc private func startQuestion() {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        let isVocabularyItem = isVocabularySelection(text)
        speakSelectedWordIfNeeded(text)
        let linkID = isVocabularyItem ? onSelectedWordQuestionStarted?(text) : nil
        let selectedContext = onAskSelectedText?(text) ?? nil
        let prompt = isVocabularyItem ? wordPrompt(for: text, context: selectedContext ?? "") : sentencePrompt(for: text)
        let displayedQuestion = isVocabularyItem ? vocabularyBubbleTitle(for: text) : "\(AppText.explainPrefix): \(text)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true, linkID: linkID)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        clearSelectedText()
        messages.append(ChatMessage(role: "user", content: prompt))
        requestAI(linkID: linkID, linkedQuestion: displayedQuestion)
    }

    @objc private func summarizeCurrentContent() {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            askSelectedSummary(selected)
            return
        }
        askCurrentContent(mode: .summary)
    }

    private func askSelectedSummary(_ text: String) {
        guard !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }
        let title = AppText.localized("选中文字", "Selected text")
        let displayedQuestion = "\(AppText.localized("总结", "Summarize")): \(title)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        messages.append(ChatMessage(role: "user", content: AIPromptStore.summaryPrompt(title: title, text: text)))
        requestAI()
    }

    @objc private func translateCurrentContent() {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            askSelectedTranslation(selected)
            return
        }
        askCurrentContent(mode: .translation)
    }

    private func askSelectedTranslation(_ text: String) {
        guard !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }
        let title = AppText.localized("选中文字", "Selected text")
        let displayedQuestion = "\(AppText.localized("翻译", "Translate")): \(title)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        requestTranslation(title: title, text: text)
    }

    private enum CurrentContentMode {
        case summary
        case translation
    }

    private func askCurrentContent(mode: CurrentContentMode) {
        guard !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }
        let contentProvider = mode == .translation ? onTranslateCurrentContent : onSummarizeCurrentContent
        contentProvider? { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content,
                      !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NSSound.beep()
                    return
                }

                let title = mode == .summary ? AppText.localized("总结", "Summarize") : AppText.localized("翻译", "Translate")
                let displayedQuestion = "\(title): \(content.title)"
                self.appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false)
                self.recordTranscript(role: AppText.userRole, text: displayedQuestion)
                if mode == .translation {
                    self.requestTranslation(title: content.title, text: content.text)
                    return
                }

                let prompt = AIPromptStore.summaryPrompt(title: content.title, text: content.text)
                self.messages.append(ChatMessage(role: "user", content: prompt))
                self.requestAI()
            }
        }
    }

    private func isVocabularySelection(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 80 else { return false }
        let words = normalized.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*(\s+[A-Za-z][A-Za-z'’-]*){0,4}$"#, options: .regularExpression) != nil
    }

    private func isSingleEnglishWord(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 40 else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*$"#, options: .regularExpression) != nil
    }

    private func speakSelectedWordIfNeeded(_ text: String) {
        guard AISettingsStore.speakSelectedWordEnabled,
              isSingleEnglishWord(text) else {
            return
        }
        speakWord(text)
    }

    private func speakWord(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        speechSynthesizer.speak(utterance)
    }

    private func wordPrompt(for word: String, context: String) -> String {
        AIPromptStore.wordPrompt(for: word, context: context)
    }

    private func sentencePrompt(for text: String) -> String {
        AIPromptStore.sentencePrompt(for: text)
    }

    @objc private func sendFollowUp() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        inputField.stringValue = ""
        appendBubble(role: AppText.userRole, text: text, collapsible: false)
        recordTranscript(role: AppText.userRole, text: text)
        enqueueFollowUp(question: text)
    }

    private func enqueueFollowUp(question: String) {
        let context = followUpContextIncludingSelection()
        if let onDocumentQuestionPrompt {
            setBusy(true, text: AppText.thinking)
            onDocumentQuestionPrompt(question, context) { [weak self] prompt in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setBusy(false, text: "")
                    if let prompt {
                        self.messages.append(ChatMessage(role: "user", content: prompt))
                        self.requestAI()
                        return
                    }
                    self.enqueueCurrentReadingFollowUp(question: question, context: context)
                }
            }
            return
        }

        enqueueCurrentReadingFollowUp(question: question, context: context)
    }

    private func followUpContextIncludingSelection() -> String {
        let transcript = transcriptContext()
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return transcript }

        let nearbyContext = (onAskSelectedText?(selected) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if transcript != AppText.none {
            parts.append("【对话上下文】\n\(transcript)")
        }
        parts.append("【当前选中内容】\n\(selected)")
        if !nearbyContext.isEmpty, nearbyContext != selected {
            parts.append("【选中内容附近上下文】\n\(nearbyContext)")
        }
        return String(parts.joined(separator: "\n\n").suffix(3000))
    }

    private func enqueueCurrentReadingFollowUp(question: String, context: String) {
        guard let onCurrentReadingContent else {
            messages.append(ChatMessage(role: "user", content: AIPromptStore.followUpPrompt(context: context, text: question)))
            requestAI()
            return
        }

        onCurrentReadingContent { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }
                if let content, !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.messages.append(ChatMessage(role: "user", content: AIPromptStore.readingFollowUpPrompt(
                        readingText: content.text,
                        context: context,
                        question: question
                    )))
                } else {
                    self.messages.append(ChatMessage(role: "user", content: AIPromptStore.followUpPrompt(context: context, text: question)))
                }
                self.requestAI()
            }
        }
    }

    private func transcriptContext() -> String {
        guard !transcriptEntries.isEmpty else { return AppText.none }
        let context = transcriptEntries.map { entry in
            "\(entry.role)：\n\(entry.content)"
        }.joined(separator: "\n\n")
        return String(context.suffix(1000))
    }

    private func recordTranscript(role: String, text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        transcriptEntries.append(TranscriptEntry(role: role, content: content))
    }

    private func installInteractionMonitor() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                self.ignoreEmptySelectionUntil = Date().addingTimeInterval(1.5)
            }
            return event
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let bubble = obj.object as? ChatBubbleTextField {
            restoreBubbleRendering(bubble)
            return
        }

        guard obj.object as? NSTextField === inputField else { return }
        isEditingFollowUp = false
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
            sendFollowUp()
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let bubble = obj.object as? ChatBubbleTextField {
            DispatchQueue.main.async { [weak self, weak bubble] in
                guard let self, let bubble else { return }
                self.restoreBubbleRendering(bubble)
            }
            return
        }

        guard obj.object as? NSTextField === inputField else { return }
        isEditingFollowUp = true
    }

    private func requestAI(linkID: String? = nil, linkedQuestion: String? = nil) {
        setBusy(true, text: AppText.thinking)
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating, linkID: linkID)
        var streamedText = ""
        client.sendStream(messages: messages, onDelta: { [weak self, weak assistantBody] delta in
            DispatchQueue.main.async {
                guard let self = self, let assistantBody = assistantBody else { return }
                streamedText += delta
                let visibleText = AIClient.visibleAnswer(from: streamedText)
                self.scheduleStreamUpdate(assistantBody, text: visibleText.isEmpty ? AppText.generating : visibleText)
            }
        }, completion: { [weak self, weak assistantBody] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.flushStreamUpdate(assistantBody)
                self.setBusy(false, text: "")
                switch result {
                case .success(let content):
                    self.recordTranscript(role: AppText.aiRole, text: content)
                    self.messages.append(ChatMessage(role: "assistant", content: content))
                    if let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.aiRole, text: content)
                    }
                    if let linkID, let linkedQuestion {
                        self.onLinkedAnswerCompleted?(linkID, linkedQuestion, content)
                    }
                case .failure(let error):
                    let message = self.userFacingAIError(error)
                    if streamedText.isEmpty, let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: message)
                    } else {
                        self.appendBubble(role: AppText.errorRole, text: message)
                    }
                }
            }
        })
    }

    private func requestTranslation(title: String, text: String) {
        setBusy(true, text: AppText.localized("翻译中", "Translating"))
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating, renderMarkdown: false)
        let chunks = translationChunks(from: text)
        var translatedChunks = Array(repeating: "", count: chunks.count)

        func translateChunk(_ index: Int) {
            guard index < chunks.count else {
                let merged = translatedChunks
                    .map { indentedTranslationText($0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                recordTranscript(role: AppText.aiRole, text: merged)
                messages.append(ChatMessage(role: "assistant", content: merged))
                updateBubble(assistantBody, role: AppText.aiRole, text: merged, renderMarkdown: false)
                setBusy(false, text: "")
                return
            }

            let status = chunks.count > 1
                ? AppText.localized("翻译中 \(index + 1)/\(chunks.count)", "Translating \(index + 1)/\(chunks.count)")
                : AppText.localized("翻译中", "Translating")
            statusLabel.stringValue = status
            updateBubble(assistantBody, role: AppText.aiRole, text: partialTranslationText(translatedChunks, currentIndex: index), renderMarkdown: false)

            let prompt = AIPromptStore.translationPrompt(title: title, text: chunks[index])
            client.send(messages: [
                ChatMessage(role: "system", content: AIPromptStore.systemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ]) { [weak self, weak assistantBody] result in
                DispatchQueue.main.async {
                    guard let self, let assistantBody else { return }
                    switch result {
                    case .success(let content):
                        translatedChunks[index] = content
                        self.updateBubble(
                            assistantBody,
                            role: AppText.aiRole,
                            text: self.partialTranslationText(translatedChunks, currentIndex: index + 1),
                            renderMarkdown: false
                        )
                        translateChunk(index + 1)
                    case .failure(let error):
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: self.userFacingAIError(error))
                        self.setBusy(false, text: "")
                    }
                }
            }
        }

        translateChunk(0)
    }

    private func translationChunks(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3600 else { return [trimmed] }

        let paragraphs = trimmed.components(separatedBy: "\n\n")
        guard paragraphs.count > 1 else {
            let midpoint = trimmed.index(trimmed.startIndex, offsetBy: trimmed.count / 2)
            let split = trimmed[midpoint...].firstIndex { ".!?。！？\n".contains($0) } ?? midpoint
            return [
                String(trimmed[..<split]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(trimmed[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
            ].filter { !$0.isEmpty }
        }

        let target = max(1, trimmed.count / 2)
        var first: [String] = []
        var second: [String] = []
        var firstLength = 0
        for paragraph in paragraphs {
            if firstLength < target || second.isEmpty {
                first.append(paragraph)
                firstLength += paragraph.count
            } else {
                second.append(paragraph)
            }
        }
        return [first.joined(separator: "\n\n"), second.joined(separator: "\n\n")]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func partialTranslationText(_ chunks: [String], currentIndex: Int) -> String {
        let completed = chunks[..<currentIndex]
            .map { indentedTranslationText($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if completed.isEmpty { return AppText.generating }
        return completed + "\n\n" + AppText.generating
    }

    private func indentedTranslationText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return "　　" + trimmed
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func userFacingAIError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == -10 {
            return AppText.localized(
                "还没有配置当前模型的 API Key。请先打开设置，选择模型并填写 API Key。",
                "The current model does not have an API Key yet. Open Settings, choose a model, and enter the API Key."
            )
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return AppText.localized("网络不可用。请检查网络连接后再试。", "Network is unavailable. Check your connection and try again.")
            case NSURLErrorTimedOut:
                return AppText.localized("请求超时了。请稍后再试，或切换到响应更快的模型。", "The request timed out. Try again later, or switch to a faster model.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return AppText.localized("无法连接到模型服务。请检查网络，或确认当前模型服务可用。", "Cannot connect to the model service. Check your network or confirm the service is available.")
            default:
                return AppText.localized("请求模型服务失败。请检查网络和 API Key 后再试。", "The model request failed. Check your network and API Key, then try again.")
            }
        }

        if nsError.code == 401 || nsError.code == 403 {
            return AppText.localized("API Key 无效或没有权限。请在设置里检查 API Key 和所选模型。", "The API Key is invalid or lacks permission. Check the API Key and selected model in Settings.")
        }
        if nsError.code == 402 {
            return AppText.localized("账户余额不足或计费不可用。请检查对应模型服务账户。", "The account balance is insufficient or billing is unavailable. Check the account for this model service.")
        }
        if nsError.code == 404 {
            return AppText.localized("当前模型不可用。请在设置里切换模型后再试。", "The selected model is unavailable. Switch models in Settings and try again.")
        }
        if nsError.code == 429 {
            return AppText.localized("请求太频繁或额度已达上限。请稍后再试。", "Too many requests or the quota has been reached. Try again later.")
        }
        if (500...599).contains(nsError.code) {
            return AppText.localized("模型服务暂时异常。请稍后再试，或切换其他模型。", "The model service is temporarily unavailable. Try again later or switch models.")
        }

        return AppText.localized("AI 请求失败。请检查模型设置、API Key 和网络后再试。", "The AI request failed. Check the model settings, API Key, and network, then try again.")
    }

    private func setBusy(_ busy: Bool, text: String) {
        isBusy = busy
        askButton.isEnabled = !selectedText.isEmpty
        summaryButton.isEnabled = !busy
        translateButton.isEnabled = !busy
        inputField.isEnabled = !busy
        sendButton.isEnabled = !busy
        statusLabel.stringValue = text
        if busy {
            loadingDots.isHidden = false
            loadingDots.startAnimating()
        } else {
            loadingDots.stopAnimating()
            loadingDots.isHidden = true
        }
    }

    @discardableResult
    private func appendBubble(role: String, text: String, collapsible: Bool = false, renderMarkdown: Bool = true, linkID: String? = nil) -> NSTextField {
        let box = ChatBubbleView()
        box.fillColor = bubbleFillColor(role: role)
        box.borderColor = bubbleBorderColor
        box.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false

        let body = ChatBubbleTextField(wrappingLabelWithString: "")
        body.attributedStringValue = bubbleString(role: role, text: text, renderMarkdown: renderMarkdown)
        body.maximumNumberOfLines = collapsible ? 1 : 0
        body.isSelectable = true
        body.allowsEditingTextAttributes = true
        body.delegate = self
        body.onInteractionEnded = { [weak self] bubble in
            self?.restoreBubbleRendering(bubble)
        }
        body.translatesAutoresizingMaskIntoConstraints = false
        let bodyID = UUID().uuidString
        body.identifier = NSUserInterfaceItemIdentifier(bodyID)
        bubbleMetadataByID[bodyID] = BubbleMetadata(role: role, text: text, renderMarkdown: renderMarkdown, collapsible: collapsible, linkID: linkID)

        box.addSubview(body)
        let speakerButton: NSButton?
        if let word = speakerWordForBubble(role: role, text: text, linkID: linkID) {
            let button = WordSpeakerButton(title: "", target: self, action: #selector(playBubbleWord(_:)))
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = NSColor.systemBlue
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.identifier = NSUserInterfaceItemIdentifier(word)
            button.spokenWord = word
            button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
            button.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(button)
            speakerButton = button
            body.setContentHuggingPriority(.required, for: .horizontal)
            body.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            speakerButton = nil
        }
        transcriptStack.addArrangedSubview(box)
        if let linkID {
            box.identifier = NSUserInterfaceItemIdentifier(linkID)
            if bubbleBoxByLinkID[linkID] == nil || speakerButton != nil {
                bubbleBoxByLinkID[linkID] = box
            }
            if speakerButton == nil {
                box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(selectLinkedBubble(_:))))
                box.toolTip = AppText.localized("跳转到原文位置", "Jump to source location")
            }
        } else if collapsible {
            box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleCollapsedBubble(_:))))
            box.toolTip = AppText.tapToExpand
        }

        var constraints: [NSLayoutConstraint] = [
            box.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            body.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ]
        if let speakerButton {
            constraints.append(contentsOf: [
                body.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -78),
                speakerButton.leadingAnchor.constraint(equalTo: body.trailingAnchor, constant: 2),
                speakerButton.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
                speakerButton.centerYAnchor.constraint(equalTo: body.centerYAnchor),
                speakerButton.widthAnchor.constraint(equalToConstant: 54),
                speakerButton.heightAnchor.constraint(equalToConstant: 54)
            ])
        } else {
            constraints.append(body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12))
        }
        NSLayoutConstraint.activate(constraints)

        DispatchQueue.main.async { [weak self, weak box] in
            guard let self = self, let box = box else { return }
            self.transcriptStack.layoutSubtreeIfNeeded()
            box.scrollToVisible(box.bounds)
        }
        return body
    }

    private func speakerWordForBubble(role: String, text: String, linkID: String?) -> String? {
        guard linkID != nil, role == AppText.userRole else { return nil }
        let rawWord = vocabularyWord(from: text)
        return isSingleEnglishWord(rawWord) ? rawWord : nil
    }

    @objc private func playBubbleWord(_ sender: NSButton) {
        let candidate = (sender as? WordSpeakerButton)?.spokenWord ?? sender.identifier?.rawValue
        guard let word = candidate,
              isSingleEnglishWord(word) else {
            return
        }
        speakWord(word)
    }

    private func updateBubble(_ body: NSTextField, role: String, text: String, renderMarkdown: Bool = true) {
        let existingMetadata = body.identifier.flatMap { bubbleMetadataByID[$0.rawValue] }
        if let bodyID = body.identifier?.rawValue {
            bubbleMetadataByID[bodyID] = BubbleMetadata(
                role: role,
                text: text,
                renderMarkdown: renderMarkdown,
                collapsible: existingMetadata?.collapsible ?? false,
                linkID: existingMetadata?.linkID
            )
        }
        body.attributedStringValue = bubbleString(role: role, text: text, renderMarkdown: renderMarkdown)
        body.invalidateIntrinsicContentSize()
        body.superview?.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        body.superview?.scrollToVisible(body.superview?.bounds ?? body.bounds)
    }

    private func restoreBubbleRendering(_ body: NSTextField) {
        guard let bodyID = body.identifier?.rawValue,
              let metadata = bubbleMetadataByID[bodyID] else {
            return
        }
        body.attributedStringValue = bubbleString(
            role: metadata.role,
            text: metadata.text,
            renderMarkdown: metadata.renderMarkdown
        )
        body.invalidateIntrinsicContentSize()
        body.superview?.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
    }

    private func scheduleStreamUpdate(_ body: NSTextField, text: String) {
        pendingStreamText = text
        guard streamUpdateWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self, weak body] in
            guard let self, let body else { return }
            self.streamUpdateWorkItem = nil
            self.updateBubble(body, role: AppText.aiRole, text: self.pendingStreamText)
        }
        streamUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func flushStreamUpdate(_ body: NSTextField?) {
        streamUpdateWorkItem?.cancel()
        streamUpdateWorkItem = nil
        guard let body, !pendingStreamText.isEmpty else { return }
        updateBubble(body, role: AppText.aiRole, text: pendingStreamText)
    }

    private func bubbleString(role: String, text: String, renderMarkdown: Bool) -> NSAttributedString {
        if role == AppText.userRole, isVocabularyBubbleTitle(text) {
            return vocabularyTitleString(text)
        }
        return role == AppText.aiRole && renderMarkdown ? markdownString(text) : plainString(text)
    }

    @objc private func toggleCollapsedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard
            let box = recognizer.view as? ChatBubbleView,
            let body = box.subviews.compactMap({ $0 as? NSTextField }).first
        else { return }

        body.maximumNumberOfLines = body.maximumNumberOfLines == 1 ? 0 : 1
        body.invalidateIntrinsicContentSize()
        box.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        box.scrollToVisible(box.bounds)
    }

    @objc private func selectLinkedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard let box = recognizer.view as? ChatBubbleView,
              !isClickOnBubbleButton(recognizer, in: box),
              let linkID = box.identifier?.rawValue else { return }
        selectedLinkID = linkID
        updateLinkedBubbleSelection()
        onLinkedBubbleSelected?(linkID)
    }

    private func isClickOnBubbleButton(_ recognizer: NSClickGestureRecognizer, in box: ChatBubbleView) -> Bool {
        let location = recognizer.location(in: box)
        return box.subviews.contains { subview in
            subview is NSButton && subview.frame.contains(location)
        }
    }

    private func updateLinkedBubbleSelection() {
        for (linkID, box) in bubbleBoxByLinkID {
            box.borderColor = linkID == selectedLinkID
                ? NSColor.systemBlue.withAlphaComponent(0.9)
                : bubbleBorderColor
            box.needsDisplay = true
        }
    }

    private func scrollTranscriptToTop(of box: NSView) {
        transcriptStack.layoutSubtreeIfNeeded()
        guard let documentView = scrollView.documentView else {
            box.scrollToVisible(box.bounds)
            return
        }
        let boxFrame = box.convert(box.bounds, to: documentView)
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.y = min(
            max(0, boxFrame.minY - 8),
            max(0, documentView.bounds.height - clipView.bounds.height)
        )
        origin.x = 0
        clipView.animator().setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func plainString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.readerBodyFontSize),
            .foregroundColor: primaryTextColor,
            .paragraphStyle: paragraphStyle(spacing: 8)
        ])
    }

    private func vocabularyBubbleTitle(for word: String) -> String {
        "\(AppText.localized("单词", "Word"))：\(word.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func isVocabularyBubbleTitle(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("单词：")
            || normalized.hasPrefix("单词:")
            || normalized.lowercased().hasPrefix("word:")
            || isSingleEnglishWord(normalized)
    }

    private func vocabularyWord(from text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["：", ":"] {
            if let range = normalized.range(of: separator) {
                return String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return normalized
    }

    private func vocabularyTitleString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: AppFont.semibold(ofSize: Self.readerBodyFontSize),
            .foregroundColor: primaryTextColor,
            .paragraphStyle: paragraphStyle(spacing: 8)
        ])
    }

    private func markdownString(_ text: String) -> NSAttributedString {
        MarkdownRenderer.render(text, fontSize: Self.readerBodyFontSize, textColor: primaryTextColor)
    }

    private func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
        return style
    }

    private var panelBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
            : NSColor.white.withAlphaComponent(0.97)
    }

    private var primaryTextColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1)
            : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
    }

    private var secondaryTextColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1)
            : NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
    }

    private var inputBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
    }

    private var bubbleBorderColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)
            : NSColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1)
    }

    private func bubbleFillColor(role: String) -> NSColor {
        guard isDarkMode else {
            return role == AppText.userRole ? NSColor(red: 0.92, green: 0.96, blue: 1, alpha: 1) : .white
        }
        return role == AppText.userRole
            ? NSColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1)
            : NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
    }

    private func restyleTranscript() {
        let entries = transcriptStack.arrangedSubviews.compactMap { view -> BubbleMetadata? in
            guard
                let box = view as? NSBox,
                let body = box.subviews.compactMap({ $0 as? NSTextField }).first,
                let bodyID = body.identifier?.rawValue,
                let metadata = bubbleMetadataByID[bodyID]
            else {
                return nil
            }
            return metadata
        }

        if !entries.isEmpty {
            transcriptStack.arrangedSubviews.forEach { view in
                transcriptStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            bubbleMetadataByID.removeAll()
            for metadata in entries {
                appendBubble(
                    role: metadata.role,
                    text: metadata.text,
                    collapsible: metadata.collapsible,
                    renderMarkdown: metadata.renderMarkdown,
                    linkID: metadata.linkID
                )
            }
            updateLinkedBubbleSelection()
            return
        }

        for box in transcriptStack.arrangedSubviews.compactMap({ $0 as? ChatBubbleView }) {
            box.borderColor = bubbleBorderColor
            guard let body = box.subviews.compactMap({ $0 as? NSTextField }).first else { continue }
            let metadata: BubbleMetadata?
            if let bodyID = body.identifier?.rawValue {
                metadata = bubbleMetadataByID[bodyID]
            } else {
                metadata = nil
            }
            let role = metadata?.role ?? AppText.aiRole
            let fillColor = bubbleFillColor(role: role)
            box.fillColor = fillColor
            if let metadata {
                body.attributedStringValue = bubbleString(role: metadata.role, text: metadata.text, renderMarkdown: metadata.renderMarkdown)
            } else {
                box.fillColor = bubbleFillColor(role: AppText.aiRole)
                let updated = NSMutableAttributedString(attributedString: body.attributedStringValue)
                updated.addAttribute(.foregroundColor, value: primaryTextColor, range: NSRange(location: 0, length: updated.length))
                body.attributedStringValue = updated
            }
            box.needsDisplay = true
            body.needsDisplay = true
        }
        updateLinkedBubbleSelection()
        transcriptStack.needsLayout = true
        transcriptStack.layoutSubtreeIfNeeded()
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor

        askButton.target = self
        askButton.action = #selector(startQuestion)
        askButton.isBordered = false
        askButton.isEnabled = false
        askButton.wantsLayer = true
        askButton.layer?.shadowColor = NSColor(red: 0.22, green: 0.32, blue: 0.92, alpha: 1).cgColor
        askButton.layer?.shadowOpacity = 0.24
        askButton.layer?.shadowRadius = 9
        askButton.layer?.shadowOffset = CGSize(width: 0, height: -3)
        askButton.translatesAutoresizingMaskIntoConstraints = false

        summaryButton.title = AppText.localized("总结", "Summarize")
        summaryButton.controlSize = .regular
        summaryButton.font = AppFont.semibold(ofSize: 13)
        summaryButton.isDark = isDarkMode
        summaryButton.target = self
        summaryButton.action = #selector(summarizeCurrentContent)
        summaryButton.translatesAutoresizingMaskIntoConstraints = false

        translateButton.title = AppText.localized("翻译", "Translate")
        translateButton.controlSize = .regular
        translateButton.font = AppFont.semibold(ofSize: 13)
        translateButton.isDark = isDarkMode
        translateButton.target = self
        translateButton.action = #selector(translateCurrentContent)
        translateButton.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        transcriptStack.orientation = .vertical
        transcriptStack.alignment = .leading
        transcriptStack.spacing = 10
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = transcriptStack

        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.textColor = NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingDots.isHidden = true
        loadingDots.translatesAutoresizingMaskIntoConstraints = false

        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(loadingDots)
        statusRow.addSubview(statusLabel)

        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).cgColor
        inputBar.layer?.cornerRadius = 8
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholderString = AppText.followUpPlaceholder
        inputField.font = NSFont.systemFont(ofSize: Self.readerBodyFontSize)
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(sendFollowUp)
        inputField.translatesAutoresizingMaskIntoConstraints = false

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendFollowUp)
        sendButton.contentTintColor = NSColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
        for view in [askButton, summaryButton, translateButton, scrollView, statusRow, inputBar] {
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            askButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            askButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            askButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            askButton.heightAnchor.constraint(equalToConstant: 44),

            summaryButton.topAnchor.constraint(equalTo: askButton.bottomAnchor, constant: 10),
            summaryButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            summaryButton.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -5),
            summaryButton.heightAnchor.constraint(equalToConstant: 32),

            translateButton.topAnchor.constraint(equalTo: summaryButton.topAnchor),
            translateButton.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 5),
            translateButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            translateButton.heightAnchor.constraint(equalTo: summaryButton.heightAnchor),

            scrollView.topAnchor.constraint(equalTo: summaryButton.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: statusRow.topAnchor, constant: -8),

            transcriptStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            transcriptStack.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            transcriptStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            statusRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusRow.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),
            statusRow.heightAnchor.constraint(equalToConstant: 18),

            loadingDots.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor),
            loadingDots.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            loadingDots.widthAnchor.constraint(equalToConstant: 22),
            loadingDots.heightAnchor.constraint(equalToConstant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: loadingDots.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            inputBar.heightAnchor.constraint(equalToConstant: 44),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    func refreshLanguage() {
        inputField.placeholderString = AppText.followUpPlaceholder
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        summaryButton.title = AppText.localized("总结", "Summarize")
        translateButton.title = AppText.localized("翻译", "Translate")
        summaryButton.needsDisplay = true
        translateButton.needsDisplay = true
        askButton.needsDisplay = true
        if !messages.isEmpty, messages[0].role == "system" {
            messages[0] = ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        }
    }
}

private final class ChatBubbleView: NSView {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var borderColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 8 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class LoadingDotsView: NSView {
    private var timer: Timer?
    private var phase = 0

    func startAnimating() {
        timer?.invalidate()
        phase = 0
        needsDisplay = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase = (self.phase + 1) % 3
            self.needsDisplay = true
        }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let activeColor = NSColor.systemBlue.withAlphaComponent(0.95)
        let inactiveColor = NSColor.systemBlue.withAlphaComponent(0.28)
        let radius: CGFloat = 3
        let y = bounds.midY - radius
        for index in 0..<3 {
            let color = index == phase ? activeColor : inactiveColor
            color.setFill()
            let x = CGFloat(index) * 8 + 1
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)).fill()
        }
    }
}
