import AVFoundation
import Cocoa

extension AIChatPanel {
    func appendNotice(_ text: String) {
        appendBubble(role: AppText.localized("提示", "Note"), text: text, collapsible: false, renderMarkdown: false)
    }

    @objc func startQuestion() {
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
        if let linkID,
           let reusedAnswer = onLinkedWordAnswerAvailable?(linkID),
           !reusedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendBubble(role: AppText.aiRole, text: reusedAnswer, collapsible: false, renderMarkdown: true, linkID: linkID)
            recordTranscript(role: AppText.aiRole, text: reusedAnswer)
            appendMessage(ChatMessage(role: "user", content: prompt))
            appendMessage(ChatMessage(role: "assistant", content: reusedAnswer))
            return
        }
        appendMessage(ChatMessage(role: "user", content: prompt))
        requestAI(linkID: linkID, linkedQuestion: displayedQuestion)
    }

    @objc func summarizeCurrentContent() {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            askSelectedSummary(selected)
            return
        }
        askCurrentContent(mode: .summary)
    }

    func askSelectedSummary(_ text: String) {
        guard !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }
        let title = AppText.localized("选中文字", "Selected text")
        let displayedQuestion = "\(AppText.localized("总结", "Summarize")): \(title)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        appendMessage(ChatMessage(role: "user", content: AIPromptStore.summaryPrompt(title: title, text: text)))
        requestAI()
    }

    @objc func translateCurrentContent() {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            askSelectedTranslation(selected)
            return
        }
        askCurrentContent(mode: .translation)
    }

    func askSelectedTranslation(_ text: String) {
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

    enum CurrentContentMode {
        case summary
        case translation
    }

    func askCurrentContent(mode: CurrentContentMode) {
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
                self.appendMessage(ChatMessage(role: "user", content: prompt))
                self.requestAI()
            }
        }
    }

    func isVocabularySelection(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 80 else { return false }
        let words = normalized.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*(\s+[A-Za-z][A-Za-z'’-]*){0,4}$"#, options: .regularExpression) != nil
    }

    func isSingleEnglishWord(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 40 else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*$"#, options: .regularExpression) != nil
    }

    func speakSelectedWordIfNeeded(_ text: String) {
        guard AISettingsStore.speakSelectedWordEnabled,
              isSingleEnglishWord(text) else {
            return
        }
        speakWord(text)
    }

    func speakWord(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        speechSynthesizer.speak(utterance)
    }

    func wordPrompt(for word: String, context: String) -> String {
        AIPromptStore.wordPrompt(for: word, context: context)
    }

    func sentencePrompt(for text: String) -> String {
        AIPromptStore.sentencePrompt(for: text)
    }

    @objc func sendFollowUp() {
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

    func enqueueFollowUp(question: String) {
        let context = followUpContextIncludingSelection()
        if let onDocumentQuestionPrompt {
            setBusy(true, text: AppText.thinking)
            onDocumentQuestionPrompt(question, context) { [weak self] prompt in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setBusy(false, text: "")
                    if let prompt {
                        self.appendMessage(ChatMessage(role: "user", content: prompt))
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

    func followUpContextIncludingSelection() -> String {
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

    func enqueueCurrentReadingFollowUp(question: String, context: String) {
        guard let onCurrentReadingContent else {
            appendMessage(ChatMessage(role: "user", content: AIPromptStore.followUpPrompt(context: context, text: question)))
            requestAI()
            return
        }

        onCurrentReadingContent { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }
                if let content, !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.appendMessage(ChatMessage(role: "user", content: AIPromptStore.readingFollowUpPrompt(
                        readingText: content.text,
                        context: context,
                        question: question
                    )))
                } else {
                    self.appendMessage(ChatMessage(role: "user", content: AIPromptStore.followUpPrompt(context: context, text: question)))
                }
                self.requestAI()
            }
        }
    }

    func transcriptContext() -> String {
        guard !transcriptEntries.isEmpty else { return AppText.none }
        let context = transcriptEntries.map { entry in
            "\(entry.role)：\n\(entry.content)"
        }.joined(separator: "\n\n")
        return String(context.suffix(1000))
    }

    func recordTranscript(role: String, text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        transcriptEntries.append(TranscriptEntry(role: role, content: content))
    }

    func installInteractionMonitor() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if self.shouldPreserveSelection(for: event) {
                self.preserveActiveBubbleSelection()
            } else {
                self.clearSelectionForNonPreservingInteraction()
            }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                self.ignoreEmptySelectionUntil = Date().addingTimeInterval(1.5)
            }
            return event
        }
    }

    func shouldPreserveSelection(for event: NSEvent) -> Bool {
        isMouseEvent(event, inside: inputBar)
            || isMouseEvent(event, inside: sendButton)
            || [askButton, summaryButton, translateButton].contains { isMouseEvent(event, inside: $0) }
    }

    func isMouseEvent(_ event: NSEvent, inside view: NSView) -> Bool {
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point)
    }

    func preserveActiveBubbleSelection() {
        guard let bubble = activeBubbleTextField,
              activeBubbleSelectionRange != nil else { return }
        let selected = activeBubbleSelectedText
        guard !selected.isEmpty else { return }
        setSelectedBubbleText(selected)
        restoreBubbleRendering(bubble)
    }

    func clearSelectionForNonPreservingInteraction() {
        clearActiveBubbleSelection(restoreRendering: true, clearSelectedTextState: false)
        updateSelectedText("")
        onNonFollowUpSelectionInteraction?()
    }

    func clearActiveBubbleSelection(restoreRendering: Bool, clearSelectedTextState: Bool = true) {
        guard let bubble = activeBubbleTextField else { return }
        bubble.clearTextSelection()
        activeBubbleSelectionRange = nil
        activeBubbleSelectedText = ""
        if restoreRendering {
            restoreBubbleRendering(bubble)
        }
        activeBubbleTextField = nil
        if clearSelectedTextState {
            updateSelectedText("")
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let bubble = obj.object as? ChatBubbleTextField {
            if captureBubbleSelection(from: bubble) {
                return
            }
            if activeBubbleTextField === bubble,
               activeBubbleSelectionRange != nil,
               !activeBubbleSelectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setSelectedBubbleText(activeBubbleSelectedText)
                restoreBubbleRendering(bubble)
                return
            }
            restoreBubbleRendering(bubble)
            if activeBubbleTextField === bubble {
                activeBubbleSelectionRange = nil
                activeBubbleSelectedText = ""
                activeBubbleTextField = nil
            }
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
            activeBubbleTextField = bubble
            return
        }

        guard obj.object as? NSTextField === inputField else { return }
        isEditingFollowUp = true
    }

    func requestAI(linkID: String? = nil, linkedQuestion: String? = nil) {
        trimMessagesIfNeeded()
        let requestID = UUID()
        activeRequestID = requestID
        let requestMessages = messages
        lastFailedAIRequest = nil
        setBusy(true, text: AppText.thinking)
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating, linkID: linkID)
        activeAssistantBody = assistantBody
        var streamedText = ""
        currentStreamTask = client.sendStream(messages: messages, onDelta: { [weak self, weak assistantBody] delta in
            DispatchQueue.main.async {
                guard let self = self, let assistantBody = assistantBody else { return }
                guard self.activeRequestID == requestID else { return }
                streamedText += delta
                let visibleText = AIClient.visibleAnswer(from: streamedText)
                self.scheduleStreamUpdate(assistantBody, text: visibleText.isEmpty ? AppText.generating : visibleText)
            }
        }, completion: { [weak self, weak assistantBody] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.activeRequestID == requestID || self.cancelledRequestIDs.contains(requestID) else { return }
                if self.cancelledRequestIDs.remove(requestID) != nil {
                    return
                }
                self.activeRequestID = nil
                self.currentStreamTask = nil
                self.activeAssistantBody = nil
                self.flushStreamUpdate(assistantBody)
                self.setBusy(false, text: "")
                switch result {
                case .success(let content):
                    self.recordTranscript(role: AppText.aiRole, text: content)
                    self.appendMessage(ChatMessage(role: "assistant", content: content))
                    if let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.aiRole, text: content)
                    }
                    if let linkID, let linkedQuestion {
                        let visible = AIClient.visibleAnswer(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !visible.isEmpty {
                            self.onLinkedAnswerCompleted?(linkID, linkedQuestion, visible)
                        }
                    }
                case .failure(let error):
                    self.lastFailedAIRequest = FailedAIRequest(messages: requestMessages, linkID: linkID, linkedQuestion: linkedQuestion)
                    let message = self.userFacingAIError(error)
                    if streamedText.isEmpty, let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: message)
                    } else {
                        self.appendBubble(role: AppText.errorRole, text: message)
                    }
                    self.appendRetryButton()
                }
            }
        })
    }

    func appendRetryButton() {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: AppText.localized("重试", "Retry"), target: self, action: #selector(retryLastFailedRequest(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.systemBlue.cgColor
        button.layer?.cornerRadius = 7
        button.attributedTitle = NSAttributedString(
            string: AppText.localized("重试", "Retry"),
            attributes: [
                .font: AppFont.semibold(ofSize: 13),
                .foregroundColor: NSColor.white
            ]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)
        transcriptStack.addArrangedSubview(row)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            row.heightAnchor.constraint(equalToConstant: 38),
            button.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])

        DispatchQueue.main.async { [weak self, weak row] in
            guard let self, let row else { return }
            self.transcriptStack.layoutSubtreeIfNeeded()
            row.scrollToVisible(row.bounds)
        }
    }

    @objc func retryLastFailedRequest(_ sender: NSButton) {
        guard !isBusy, let request = lastFailedAIRequest else { return }
        lastFailedAIRequest = nil
        messages = request.messages
        trimMessagesIfNeeded()
        requestAI(linkID: request.linkID, linkedQuestion: request.linkedQuestion)
    }

    @objc func cancelCurrentRequest() {
        guard isBusy else { return }
        if let activeRequestID {
            cancelledRequestIDs.insert(activeRequestID)
        }
        if let linkID = activeAssistantBody?.superview?.identifier?.rawValue {
            onLinkedAnswerFailed?(linkID)
        }
        activeRequestID = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
        if let activeAssistantBody {
            updateBubble(activeAssistantBody, role: AppText.localized("提示", "Note"), text: AppText.localized("已取消。", "Cancelled."), renderMarkdown: false)
        } else {
            appendBubble(role: AppText.localized("提示", "Note"), text: AppText.localized("已取消。", "Cancelled."), collapsible: false, renderMarkdown: false)
        }
        activeAssistantBody = nil
        setBusy(false, text: "")
    }

    func requestTranslation(title: String, text: String) {
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
                appendMessage(ChatMessage(role: "assistant", content: merged))
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

    func translationChunks(from text: String) -> [String] {
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

    func partialTranslationText(_ chunks: [String], currentIndex: Int) -> String {
        let completed = chunks[..<currentIndex]
            .map { indentedTranslationText($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if completed.isEmpty { return AppText.generating }
        return completed + "\n\n" + AppText.generating
    }

    func indentedTranslationText(_ text: String) -> String {
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

    func userFacingAIError(_ error: Error) -> String {
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

    func setBusy(_ busy: Bool, text: String) {
        isBusy = busy
        askButton.isEnabled = !selectedText.isEmpty
        summaryButton.isEnabled = !busy
        translateButton.isEnabled = !busy
        inputField.isEnabled = !busy
        sendButton.isEnabled = !busy
        statusLabel.stringValue = text
        if busy {
            loadingDots.isHidden = false
            cancelRequestButton.isHidden = false
            loadingDots.startAnimating()
        } else {
            loadingDots.stopAnimating()
            loadingDots.isHidden = true
            cancelRequestButton.isHidden = true
        }
    }
}
