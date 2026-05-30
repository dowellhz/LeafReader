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
        guard !isBusy else { return }
        guard canUseSelectedModel() else {
            onSettingsRequired?()
            return
        }
        let displayedQuestion = selectedTextActionTitle(actionTitle: AppText.localized("总结", "Summarize"), text: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        let title = trimmedText(text)
        appendMessage(ChatMessage(role: "user", content: AIPromptStore.summaryPrompt(title: title, text: text)))
        requestAI()
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
        guard !isBusy else { return }
        guard canUseSelectedModel() else {
            onSettingsRequired?()
            return
        }
        let displayedQuestion = selectedTextActionTitle(actionTitle: AppText.localized("翻译", "Translate"), text: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        let title = trimmedText(text)
        requestTranslation(title: title, text: text)
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
