import Cocoa

extension AIChatPanel {
    func requestAI(linkID: String? = nil, linkedQuestion: String? = nil) {
        trimMessagesIfNeeded()
        let requestID = UUID()
        let requestMessages = messages
        lastFailedAIRequest = nil
        setBusy(true, text: AppText.thinking)
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating, linkID: linkID, persist: false)
        requestState.begin(id: requestID, assistantBody: assistantBody)
        var streamedText = ""
        requestState.currentStreamTask = client.sendStream(messages: messages, onDelta: { [weak self, weak assistantBody] delta in
            DispatchQueue.main.async {
                guard let self = self, let assistantBody = assistantBody else { return }
                guard self.requestState.isActive(requestID) else { return }
                streamedText += delta
                let visibleText = AIClient.visibleAnswer(from: streamedText)
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
                    let finalContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    self.recordTranscript(role: AppText.aiRole, text: content)
                    self.appendMessage(ChatMessage(role: "assistant", content: content))
                    if let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.aiRole, text: content, notify: false)
                        self.persistBubbleIfNeeded(assistantBody)
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
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: message, notify: false)
                    } else {
                        self.appendBubble(role: AppText.errorRole, text: message, persist: false)
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

        scheduleTranscriptLayout(scrollTarget: row, forceScroll: true)
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
        let chunks = translationChunks(from: text)
        var translatedChunks = Array(repeating: "", count: chunks.count)

        func translateChunk(_ index: Int) {
            guard requestState.isActive(requestID) else { return }
            guard index < chunks.count else {
                let merged = translatedChunks
                    .map { indentedTranslationText($0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                let finalContent = merged.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        self.requestState.finish(id: requestID)
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: self.userFacingAIError(error), notify: false)
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
