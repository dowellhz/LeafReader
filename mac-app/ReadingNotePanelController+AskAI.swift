import Cocoa

extension ReadingNotePanelController {
    func installAskInputKeyMonitor() {
        editorState.askInputKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleAskInputKeyDown(event) ?? event
        }
    }

    func setAskInputVisible(_ visible: Bool) {
        askInputContainer.isHidden = !visible
        textView.isEditable = !visible
        if !visible, window?.firstResponder === askInputField.currentEditor() {
            window?.makeFirstResponder(textView)
        }
    }

    func refreshAIToolbar() {
        let enabled = !aiRunner.isRunning
        aiActionButtons.forEach { $0.isEnabled = enabled }
        if isAskInputVisible {
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

    @objc func explainSelection(_ sender: NSButton) {
        runAIAction(.explain, title: AppText.localized("解析", "Explain"))
    }

    @objc func translateSelection(_ sender: NSButton) {
        runAIAction(.translate, title: AppText.localized("翻译", "Translate"))
    }

    @objc func summarizeSelection(_ sender: NSButton) {
        runAIAction(.summarize, title: AppText.localized("总结", "Summarize"))
    }

    @objc func polishSelection(_ sender: NSButton) {
        runAIAction(
            .polish,
            title: AppText.localized("整理", "Organize"),
            replaceSelection: true,
            renderMarkdownReplacement: true
        )
    }

    @objc func showAskInput(_ sender: NSButton) {
        let selected = selectedText()
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        editorState.pendingAskSelectedText = selected
        askInputField.stringValue = ""
        aiToolbarContainer.isHidden = true
        positionAskInputNearSelection()
        setAskInputVisible(true)
        window?.makeFirstResponder(askInputField)
    }

    @objc func submitAskQuestion(_ sender: Any?) {
        let question = askInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = makeAskRequest(question: question) else { return }
        runAskQuestion(request)
    }

    private func handleAskInputKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === window,
              isAskInputVisible,
              let shortcut = ReadingNoteEditingShortcut.shortcut(for: event),
              shortcut.canForwardToFieldEditor else {
            return event
        }

        window?.makeFirstResponder(askInputField)
        guard let editor = askInputField.currentEditor() else { return nil }
        editor.performReadingNoteEditingShortcut(shortcut)
        return nil
    }

    func runAIAction(
        _ action: AITextActionRunner.Action,
        title: String,
        sourceText: String? = nil,
        replaceSlashTrigger: Bool = false,
        replaceSelection: Bool = false,
        renderMarkdownReplacement: Bool = false
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
        let insertionMode = aiInsertionMode(
            title: title,
            selectionRange: selectionRange,
            replaceSlashTrigger: replaceSlashTrigger,
            replaceSelection: replaceSelection,
            renderMarkdownReplacement: renderMarkdownReplacement
        )
        removeAIPlaceholder()
        let requestID = editorState.beginAIRequest()
        setRunning(true, title: title)
        aiToolbarContainer.isHidden = true
        if insertionMode.usesPlaceholder {
            appendAIPlaceholder(title: title)
        }
        aiRunner.run(action: action, text: text, noteContext: textView.string) { [weak self] result in
            guard let self else { return }
            guard self.editorState.canApplyAIResult(requestID) else { return }
            self.editorState.finishAIRequest(requestID)
            self.setRunning(false, title: "")
            switch result {
            case .success(let output):
                let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                self.applyAIOutput(value, insertionMode: insertionMode)
            case .failure(let error):
                if insertionMode.usesPlaceholder {
                    self.removeAIPlaceholder()
                }
                self.statusLabel.stringValue = self.userFacingError(error)
            }
        }
    }

    private func aiInsertionMode(
        title: String,
        selectionRange: NSRange,
        replaceSlashTrigger: Bool,
        replaceSelection: Bool,
        renderMarkdownReplacement: Bool
    ) -> ReadingNoteAIInsertionMode {
        if replaceSlashTrigger {
            return .replaceSlashTrigger
        }
        if replaceSelection {
            return .replaceSelection(selectionRange, renderMarkdown: renderMarkdownReplacement)
        }
        return .replacePlaceholder(title: title)
    }

    private func applyAIOutput(_ value: String, insertionMode: ReadingNoteAIInsertionMode) {
        switch insertionMode {
        case .appendSection(let title):
            appendAISection(title: title, body: value)
        case .replacePlaceholder(let title):
            replaceAIPlaceholder(title: title, body: value)
        case .replaceSelection(let range, let renderMarkdown):
            if renderMarkdown {
                replaceSelectionWithMarkdown(value, selectionRange: range)
            } else {
                replaceSelectedText(in: range, with: value)
            }
        case .replaceSlashTrigger:
            replaceCurrentSlashTrigger(with: value)
        }
    }

    private func replaceSelectionWithMarkdown(_ value: String, selectionRange: NSRange) {
        let markdown = ReadingNoteAITextPolicy.markdownBody(from: value)
        let rendered = MarkdownRenderer.render(
            markdown,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        replaceSelectedText(in: selectionRange, with: rendered)
    }

    private func makeAskRequest(question: String) -> AskRequest? {
        guard !question.isEmpty else {
            NSSound.beep()
            return nil
        }
        let selected = editorState.pendingAskSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        setAskInputVisible(false)
        askInputField.stringValue = ""
        window?.makeFirstResponder(textView)
        removeAIPlaceholder()
        let requestID = editorState.beginAIRequest()
        setRunning(true, title: AppText.localized("问 AI", "Ask AI"))
        appendAIPlaceholder(title: request.question)
        if let onDocumentQuestionPrompt {
            onDocumentQuestionPrompt(documentQuestionPromptRequest(for: request)) { [weak self] prompt in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.editorState.canApplyAIResult(requestID) else { return }
                    if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.runAskPrompt(prompt, request: request, requestID: requestID)
                    } else {
                        self.runAskFallback(request, requestID: requestID)
                    }
                }
            }
            return
        }
        runAskFallback(request, requestID: requestID)
    }

    private func documentQuestionPromptRequest(for request: AskRequest) -> DocumentQuestionPromptRequest {
        DocumentQuestionPromptRequest(
            question: request.question,
            questionSubject: request.selectedText,
            context: ReadingNoteAITextPolicy.documentContext(
                selectedText: request.selectedText,
                noteMarkdown: markdownFromEditor(),
                isChinese: AppText.isChinese
            )
        )
    }

    private func runAskPrompt(_ prompt: String, request: AskRequest, requestID: UUID) {
        aiRunner.runPrompt(prompt, systemPrompt: AIPromptStore.compactSystemPrompt()) { [weak self] result in
            self?.finishAskQuestion(result, request: request, requestID: requestID)
        }
    }

    private func runAskFallback(_ request: AskRequest, requestID: UUID) {
        aiRunner.runQuestion(
            question: request.question,
            selectedText: request.selectedText,
            systemPrompt: AIPromptStore.compactSystemPrompt()
        ) { [weak self] result in
            self?.finishAskQuestion(result, request: request, requestID: requestID)
        }
    }

    private func finishAskQuestion(_ result: Result<String, Error>, request: AskRequest, requestID: UUID) {
        guard editorState.canApplyAIResult(requestID) else { return }
        editorState.finishAIRequest(requestID)
        setRunning(false, title: "")
        switch result {
        case .success(let output):
            let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            replaceAIPlaceholder(title: request.question, body: value)
            editorState.pendingAskSelectedText = ""
        case .failure(let error):
            removeAIPlaceholder()
            statusLabel.stringValue = userFacingError(error)
        }
    }

    private func setRunning(_ running: Bool, title: String) {
        statusLabel.stringValue = running ? AppText.localized("\(title)中...", "\(title)...") : ""
        refreshAIToolbar()
    }

    private func userFacingError(_ error: Error) -> String {
        ReadingNoteAITextPolicy.userFacingError(error)
    }
}
