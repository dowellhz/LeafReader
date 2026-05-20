import AVFoundation
import Cocoa

extension AIChatPanel {
    func appendNotice(_ text: String) {
        appendBubble(role: AppText.localized("提示", "Note"), text: text, collapsible: false, renderMarkdown: false)
    }

    @objc func startQuestion() {
        let text = trimmedText(selectedText)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        let isVocabularyItem = isVocabularySelection(text)
        speakSelectedWordIfNeeded(text)
        let linkID = isVocabularyItem ? onSelectedWordQuestionStarted?(text) : nil
        if let linkID, hasLinkedBubble(id: linkID) {
            clearSelectedText()
            scrollToLinkedBubble(id: linkID)
            return
        }
        let selectedContext = onAskSelectedText?(text) ?? nil
        let prompt = isVocabularyItem ? wordPrompt(for: text, context: selectedContext ?? "") : sentencePrompt(for: text)
        let displayedQuestion = isVocabularyItem ? vocabularyBubbleTitle(for: text) : selectedTextActionTitle(actionTitle: AppText.explainPrefix, text: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true, linkID: linkID)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        clearSelectedText()
        if let linkID,
           let reusedAnswer = onLinkedWordAnswerAvailable?(linkID),
           hasTrimmedText(reusedAnswer) {
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
        let selected = trimmedText(selectedText)
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
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }
        let displayedQuestion = selectedTextActionTitle(actionTitle: AppText.localized("翻译", "Translate"), text: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        let title = trimmedText(text)
        requestTranslation(title: title, text: text)
    }

    func selectedTextActionTitle(actionTitle: String, text: String) -> String {
        "\(actionTitle): \(trimmedText(text))"
    }

    func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasTrimmedText(_ text: String) -> Bool {
        !trimmedText(text).isEmpty
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

    func isVocabularySelection(_ text: String) -> Bool {
        VocabularyTextPolicy.isVocabularySelection(text)
    }

    func isSingleEnglishWord(_ text: String) -> Bool {
        VocabularyTextPolicy.isSingleEnglishWord(text)
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
        speechSynthesizer.speak(SpeechUtteranceFactory.utterance(for: text))
    }

    func wordPrompt(for word: String, context: String) -> String {
        AIPromptStore.wordPrompt(for: word, context: context)
    }

    func sentencePrompt(for text: String) -> String {
        AIPromptStore.sentencePrompt(for: text)
    }

    @objc func sendFollowUp() {
        let text = trimmedText(inputField.stringValue)
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
        let selected = trimmedText(selectedText)
        guard !selected.isEmpty else { return transcript }

        let nearbyContext = trimmedText(onAskSelectedText?(selected) ?? "")
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
                if let content, self.hasTrimmedText(content.text) {
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
        let content = trimmedText(text)
        guard !content.isEmpty else { return }
        transcriptEntries.append(TranscriptEntry(role: role, content: content))
    }

}
