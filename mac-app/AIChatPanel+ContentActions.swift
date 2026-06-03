import Cocoa

extension AIChatPanel {
    enum CurrentContentMode {
        case summary
        case translation
    }

    @objc func summarizeCurrentContent() {
        let selected = trimmedText(selectedText)
        if !selected.isEmpty {
            askSelectedSummary(selected)
            return
        }
        askCurrentContent(mode: .summary)
    }

    func askSelectedSummary(_ text: String) {
        let title = trimmedText(text)
        askSelectedTextAction(
            title: AppText.localized("总结", "Summarize"),
            text: text,
            prompt: AIPromptStore.summaryPrompt(title: title, text: text)
        )
    }

    @objc func analyzeDifficultSentenceCurrentContent() {
        let selected = trimmedText(selectedText)
        guard !selected.isEmpty else { return }
        askSelectedTextAction(
            title: AppText.localized("难句", "Difficult sentence"),
            text: selected,
            prompt: AIPromptStore.difficultSentencePrompt(for: selected)
        )
    }

    @objc func translateCurrentContent() {
        let selected = trimmedText(selectedText)
        if !selected.isEmpty {
            askSelectedTranslation(selected)
            return
        }
        askCurrentContent(mode: .translation)
    }

    func askSelectedTranslation(_ text: String) {
        let title = trimmedText(text)
        askSelectedTextAction(title: AppText.localized("翻译", "Translate"), text: text) { [weak self] in
            self?.requestTranslation(title: title, text: text)
        }
    }

    func askSelectedTextAction(title: String, text: String, prompt: String) {
        askSelectedTextAction(title: title, text: text) { [weak self] in
            self?.appendMessage(ChatMessage(role: "user", content: prompt))
            self?.requestAI()
        }
    }

    private func askSelectedTextAction(title: String, text: String, sendRequest: () -> Void) {
        guard !isBusy else { return }
        guard canUseSelectedModel() else {
            onSettingsRequired?()
            return
        }
        let displayedQuestion = selectedTextActionTitle(actionTitle: title, text: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        sendRequest()
    }

    func askCurrentContent(mode: CurrentContentMode) {
        guard !isBusy else { return }
        guard canUseSelectedModel() else {
            onSettingsRequired?()
            return
        }
        let contentProvider = mode == .translation ? onTranslateCurrentContent : onSummarizeCurrentContent
        contentProvider? { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content,
                      self.hasTrimmedText(content.text) else {
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
}
