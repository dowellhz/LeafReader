import Cocoa

final class AIChatPanel: NSView, NSTextFieldDelegate {
    private static let readerBodyFontSize: CGFloat = 15

    private let client = AIClient()
    private let askButton = GradientButton(title: "", target: nil, action: nil)
    private let summaryButton = NSButton(title: "", target: nil, action: nil)
    private let translateButton = NSButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let transcriptStack = FlippedStackView()
    private let statusRow = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let inputBar = NSView()
    private let inputField = NSTextField(string: "")
    private let sendButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    var onAskSelectedText: ((String) -> String?)?
    var onSummarizeCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onSettingsRequired: (() -> Void)?

    private var selectedText = ""
    private var transcriptEntries: [TranscriptEntry] = []
    private var messages: [ChatMessage] = [
        ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
    ]
    private var isBusy = false
    private var pendingStreamText = ""
    private var streamUpdateWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedText(_ text: String) {
        selectedText = text
        askButton.previewText = text
        askButton.isEnabled = !text.isEmpty
    }

    func setContentVisible(_ visible: Bool) {
        subviews.forEach { $0.isHidden = !visible }
        layer?.backgroundColor = visible
            ? NSColor.white.withAlphaComponent(0.97).cgColor
            : NSColor.clear.cgColor
        needsLayout = true
    }

    @objc private func startQuestion() {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        let selectedContext = onAskSelectedText?(text) ?? nil
        let prompt = isSingleEnglishWord(text) ? wordPrompt(for: text, context: selectedContext ?? "") : sentencePrompt(for: text)
        let displayedQuestion = "\(AppText.explainPrefix): \(text)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        messages.append(ChatMessage(role: "user", content: prompt))
        requestAI()
    }

    @objc private func summarizeCurrentContent() {
        askCurrentContent(mode: .summary)
    }

    @objc private func translateCurrentContent() {
        askCurrentContent(mode: .translation)
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
        onSummarizeCurrentContent? { [weak self] content in
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
                let prompt = mode == .summary
                    ? AIPromptStore.summaryPrompt(title: content.title, text: content.text)
                    : AIPromptStore.sentencePrompt(for: content.text)
                self.messages.append(ChatMessage(role: "user", content: prompt))
                self.requestAI()
            }
        }
    }

    private func isSingleEnglishWord(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z][A-Za-z'-]*$"#, options: .regularExpression) != nil
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
        messages.append(ChatMessage(role: "user", content: followUpPrompt(for: text)))
        requestAI()
    }

    private func followUpPrompt(for text: String) -> String {
        AIPromptStore.followUpPrompt(context: transcriptContext(), text: text)
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

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === inputField else { return }
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
            sendFollowUp()
        }
    }

    private func requestAI() {
        setBusy(true, text: AppText.thinking)
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating)
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
        askButton.isEnabled = !busy && !selectedText.isEmpty
        summaryButton.isEnabled = !busy
        translateButton.isEnabled = !busy
        inputField.isEnabled = !busy
        sendButton.isEnabled = !busy
        statusLabel.stringValue = text
        if busy {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
    }

    @discardableResult
    private func appendBubble(role: String, text: String, collapsible: Bool = false) -> NSTextField {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = NSColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1)
        box.cornerRadius = 8
        box.fillColor = role == AppText.userRole ? NSColor(red: 0.92, green: 0.96, blue: 1, alpha: 1) : .white
        box.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: "")
        body.attributedStringValue = role == AppText.aiRole ? markdownString(text) : plainString(text)
        body.maximumNumberOfLines = collapsible ? 1 : 0
        body.isSelectable = false
        body.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(body)
        transcriptStack.addArrangedSubview(box)
        if collapsible {
            box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleCollapsedBubble(_:))))
            box.toolTip = AppText.tapToExpand
        }

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            body.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ])

        DispatchQueue.main.async { [weak self, weak box] in
            guard let self = self, let box = box else { return }
            self.transcriptStack.layoutSubtreeIfNeeded()
            box.scrollToVisible(box.bounds)
        }
        return body
    }

    private func updateBubble(_ body: NSTextField, role: String, text: String) {
        body.attributedStringValue = role == AppText.aiRole ? markdownString(text) : plainString(text)
        body.invalidateIntrinsicContentSize()
        body.superview?.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        body.superview?.scrollToVisible(body.superview?.bounds ?? body.bounds)
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

    @objc private func toggleCollapsedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard
            let box = recognizer.view as? NSBox,
            let body = box.subviews.compactMap({ $0 as? NSTextField }).first
        else { return }

        body.maximumNumberOfLines = body.maximumNumberOfLines == 1 ? 0 : 1
        body.invalidateIntrinsicContentSize()
        box.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        box.scrollToVisible(box.bounds)
    }

    private func plainString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.readerBodyFontSize),
            .foregroundColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1),
            .paragraphStyle: paragraphStyle(spacing: 8)
        ])
    }

    private func markdownString(_ text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            let cleaned = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")

            let isHeading = (cleaned.hasPrefix("【") && cleaned.contains("】")) || cleaned.hasPrefix("#")
            let isBoldLine = (line.hasPrefix("**") && line.hasSuffix("**")) || (line.hasPrefix("__") && line.hasSuffix("__"))
            let isBullet = cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") || cleaned.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            let display = cleaned
                .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[-*]\s+"#, with: "• ", options: .regularExpression)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: (isHeading || isBoldLine) ? NSFont.boldSystemFont(ofSize: Self.readerBodyFontSize) : NSFont.systemFont(ofSize: Self.readerBodyFontSize),
                .foregroundColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1),
                .paragraphStyle: paragraphStyle(spacing: isHeading ? 10 : 8, headIndent: isBullet ? 18 : 0)
            ]
            output.append(NSAttributedString(string: display + "\n", attributes: attrs))
        }

        return output
    }

    private func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        return style
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
        summaryButton.bezelStyle = .rounded
        summaryButton.controlSize = .regular
        summaryButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        summaryButton.target = self
        summaryButton.action = #selector(summarizeCurrentContent)
        summaryButton.translatesAutoresizingMaskIntoConstraints = false

        translateButton.title = AppText.localized("翻译", "Translate")
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .regular
        translateButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
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

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(spinner)
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

            spinner.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor),
            spinner.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
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
        askButton.needsDisplay = true
        if !messages.isEmpty, messages[0].role == "system" {
            messages[0] = ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        }
    }
}
