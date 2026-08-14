import Cocoa

extension AIChatPanel {
    func requestAI(
        linkID: String? = nil,
        linkedQuestion: String? = nil,
        fallbackAnswer: String? = nil,
        answerSuffix: String? = nil,
        replacing assistantBodyToReplace: NSTextField? = nil
    ) {
        trimMessagesIfNeeded()
        let requestID = UUID()
        let requestMessages = messages
        lastFailedAIRequest = nil
        setBusy(true, text: AppText.thinking)
        let regenerationRequest = linkID == nil
            ? RegenerationRequest(messages: requestMessages, fallbackAnswer: fallbackAnswer, answerSuffix: answerSuffix)
            : nil
        let assistantBody: NSTextField
        if let assistantBodyToReplace {
            assistantBody = assistantBodyToReplace
            updateBubble(
                assistantBody,
                role: AppText.aiRole,
                text: AppText.generating,
                renderMarkdown: true,
                notify: false
            )
        } else {
            assistantBody = appendBubble(
                role: AppText.aiRole,
                text: AppText.generating,
                linkID: linkID,
                regenerationRequest: regenerationRequest,
                persist: false
            )
        }
        requestState.begin(id: requestID, assistantBody: assistantBody)
        var streamedText = ""
        requestState.currentStreamTask = llmAnswerProvider.answerStream(messages: messages, onDelta: { [weak self, weak assistantBody] delta in
            DispatchQueue.main.async {
                guard let self = self, let assistantBody = assistantBody else { return }
                guard self.requestState.isActive(requestID) else { return }
                streamedText += delta
                let visibleText = AIResponseTextFormatter.visibleAnswer(streamedText)
                self.scheduleStreamUpdate(assistantBody, text: visibleText.isEmpty ? AppText.generating : visibleText)
            }
        }, completion: { [weak self, weak assistantBody] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.requestState.shouldHandleCompletion(for: requestID) else { return }
                if self.requestState.consumeCancellation(for: requestID) {
                    return
                }
                self.requestState.finish(id: requestID)
                self.flushStreamUpdate(assistantBody)
                self.setBusy(false, text: "")
                switch result {
                case .success(let content):
                    let finalContent = VocabularyTagFormatter.appendSuffix(
                        to: AIResponseTextFormatter.trimmed(content),
                        suffix: answerSuffix
                    )
                    guard !finalContent.isEmpty else {
                        if let assistantBody = assistantBody {
                            self.updateBubble(
                                assistantBody,
                                role: AppText.localized("提示", "Note"),
                                text: AppText.localized("AI 没有返回内容。", "AI returned no content."),
                                renderMarkdown: false,
                                notify: false
                            )
                        }
                        return
                    }
                    self.recordTranscript(role: AppText.aiRole, text: finalContent, linkID: linkID)
                    self.appendMessage(ChatMessage(role: "assistant", content: finalContent, linkID: linkID))
                    if let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.aiRole, text: finalContent, notify: false)
                        self.persistBubbleIfNeeded(assistantBody)
                        self.scrollBubbleHeadToTopIfNeeded(linkID: linkID, body: assistantBody)
                    }
                    if let linkID, let linkedQuestion {
                        let visible = AIResponseTextFormatter.visibleAnswer(finalContent)
                        if !visible.isEmpty {
                            self.onLinkedAnswerCompleted?(linkID, linkedQuestion, visible)
                        }
                    }
                case .failure(let error):
                    self.handleAIRequestFailure(
                        error,
                        streamedText: streamedText,
                        assistantBody: assistantBody,
                        requestMessages: requestMessages,
                        linkID: linkID,
                        linkedQuestion: linkedQuestion,
                        fallbackAnswer: fallbackAnswer,
                        answerSuffix: answerSuffix
                    )
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
        button.layer?.backgroundColor = aiAccentColor.cgColor
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

        scheduleTranscriptLayout(scrollTarget: row, forceScroll: true)
    }

    @objc func retryLastFailedRequest(_ sender: NSButton) {
        guard !isBusy, let request = lastFailedAIRequest else { return }
        lastFailedAIRequest = nil
        messages = request.messages
        trimMessagesIfNeeded()
        requestAI(
            linkID: request.linkID,
            linkedQuestion: request.linkedQuestion,
            fallbackAnswer: request.fallbackAnswer,
            answerSuffix: request.answerSuffix
        )
    }

    @objc func regenerateBubble(_ sender: NSButton) {
        guard !isBusy,
              let bodyID = sender.identifier?.rawValue,
              let metadata = bubbleMetadataByID[bodyID],
              let request = metadata.regenerationRequest,
              let body = textField(forBodyID: bodyID) else {
            return
        }
        messages = request.messages
        trimMessagesIfNeeded()
        requestAI(
            fallbackAnswer: request.fallbackAnswer,
            answerSuffix: request.answerSuffix,
            replacing: body
        )
    }

    @objc func cancelCurrentRequest() {
        guard isBusy else { return }
        let assistantBody = requestState.cancelActive()
        if let linkID = assistantBody?.superview?.identifier?.rawValue {
            onLinkedAnswerFailed?(linkID)
        }
        onDocumentQuestionCancelled?()
        if let assistantBody {
            updateBubble(assistantBody, role: AppText.localized("提示", "Note"), text: AppText.localized("已取消。", "Cancelled."), renderMarkdown: false, notify: false)
        } else {
            appendBubble(role: AppText.localized("提示", "Note"), text: AppText.localized("已取消。", "Cancelled."), collapsible: false, renderMarkdown: false, persist: false)
        }
        setBusy(false, text: "")
    }

    func requestTranslation(title: String, text: String) {
        let requestID = UUID()
        setBusy(true, text: AppText.localized("翻译中", "Translating"))
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating, renderMarkdown: false, persist: false)
        requestState.begin(id: requestID, assistantBody: assistantBody)
        let chunks = AIResponseTextFormatter.translationChunks(from: text)
        var translatedChunks = Array(repeating: "", count: chunks.count)

        func translateChunk(_ index: Int) {
            guard requestState.isActive(requestID) else { return }
            guard index < chunks.count else {
                let merged = translatedChunks
                    .map { AIResponseTextFormatter.indentedTranslationText($0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                let finalContent = AIResponseTextFormatter.trimmed(merged)
                requestState.finish(id: requestID)
                setBusy(false, text: "")
                guard !finalContent.isEmpty else {
                    updateBubble(
                        assistantBody,
                        role: AppText.localized("提示", "Note"),
                        text: AppText.localized("AI 没有返回内容。", "AI returned no content."),
                        renderMarkdown: false,
                        notify: false
                    )
                    return
                }
                recordTranscript(role: AppText.aiRole, text: merged)
                appendMessage(ChatMessage(role: "assistant", content: merged))
                updateBubble(assistantBody, role: AppText.aiRole, text: merged, renderMarkdown: false, notify: false)
                persistBubbleIfNeeded(assistantBody)
                scrollBubbleHeadToTopIfNeeded(linkID: nil, body: assistantBody)
                return
            }

            let status = chunks.count > 1
                ? AppText.localized("翻译中 \(index + 1)/\(chunks.count)", "Translating \(index + 1)/\(chunks.count)")
                : AppText.localized("翻译中", "Translating")
            statusLabel.stringValue = status
            updateBubble(assistantBody, role: AppText.aiRole, text: partialTranslationText(translatedChunks, currentIndex: index), renderMarkdown: false)

            let prompt = AIPromptStore.translationPrompt(title: title, text: chunks[index])
            requestState.currentDataTask = client.send(messages: [
                ChatMessage(role: "system", content: AIPromptStore.systemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ]) { [weak self, weak assistantBody] result in
                DispatchQueue.main.async {
                    guard let self, let assistantBody else { return }
                    guard self.requestState.shouldHandleCompletion(for: requestID) else { return }
                    if self.requestState.consumeCancellation(for: requestID) {
                        self.finishTranslationRequest(requestID: requestID, busyText: "")
                        return
                    }
                    self.requestState.currentDataTask = nil
                    switch result {
                    case .success(let content):
                        translatedChunks[index] = content
                        self.updateBubble(
                            assistantBody,
                            role: AppText.aiRole,
                            text: self.partialTranslationText(translatedChunks, currentIndex: index + 1),
                            renderMarkdown: false,
                            notify: false
                        )
                        translateChunk(index + 1)
                    case .failure(let error):
                        self.finishTranslationRequest(requestID: requestID, busyText: "")
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: self.userFacingAIError(error), notify: false)
                    }
                }
            }
        }

        translateChunk(0)
    }

    func translationChunks(from text: String) -> [String] {
        AIResponseTextFormatter.translationChunks(from: text)
    }

    func partialTranslationText(_ chunks: [String], currentIndex: Int) -> String {
        AIResponseTextFormatter.partialTranslationText(chunks, currentIndex: currentIndex, generatingText: AppText.generating)
    }

    func indentedTranslationText(_ text: String) -> String {
        AIResponseTextFormatter.indentedTranslationText(text)
    }

    func finishTranslationRequest(requestID: UUID, busyText: String) {
        requestState.currentDataTask = nil
        requestState.finish(id: requestID)
        setBusy(false, text: busyText)
    }

    func userFacingAIError(_ error: Error) -> String {
        AIRequestErrorText.message(for: error)
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
