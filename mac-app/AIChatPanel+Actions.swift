import Cocoa

extension AIChatPanel {
    func appendNotice(_ text: String) {
        appendBubble(role: AppText.localized("提示", "Note"), text: text, collapsible: false, renderMarkdown: false)
    }

    @objc func startQuestion() {
        let text = trimmedText(selectedText)
        guard !text.isEmpty, !isBusy else { return }
        guard canUseSelectedModel() else {
            if handleLocalDictionaryQuestion(text) {
                return
            }
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
        recordTranscript(role: AppText.userRole, text: displayedQuestion, linkID: linkID)
        clearSelectedText()
        let answerRequest = AnswerProviderRequest(text: text, context: selectedContext ?? "", linkID: linkID)
        if let reusedAnswer = cachedVocabularyAnswerProvider().answer(for: answerRequest) {
            let answer = reusedAnswer.answer
            appendBubble(role: AppText.aiRole, text: answer, collapsible: false, renderMarkdown: true, linkID: linkID)
            recordTranscript(role: AppText.aiRole, text: answer, linkID: linkID)
            appendMessage(ChatMessage(role: "user", content: prompt, linkID: linkID))
            appendMessage(ChatMessage(role: "assistant", content: answer, linkID: linkID))
            return
        }
        appendMessage(ChatMessage(role: "user", content: prompt, linkID: linkID))
        let localAnswer = isVocabularyItem ? localOnlyAnswerProvider().answer(for: answerRequest) : nil
        let fallbackAnswer = localAnswer?.answer
        let answerSuffix = isVocabularyItem
            ? localDictionaryTagSuffix(for: text, fallbackMetadata: localAnswer?.dictionaryMetadata)
            : nil
        requestAI(
            linkID: linkID,
            linkedQuestion: displayedQuestion,
            fallbackAnswer: fallbackAnswer,
            answerSuffix: answerSuffix
        )
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

    func canUseSelectedModel() -> Bool {
        RequestAvailabilityPolicy.canUseSelectedModel()
    }

    @objc func sendFollowUp() {
        let text = trimmedText(inputField.stringValue)
        guard !text.isEmpty, !isBusy else { return }
        guard canUseSelectedModel() else {
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
            let request = DocumentQuestionPromptRequest(question: question, context: context)
            onDocumentQuestionPrompt(request) { [weak self] prompt in
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
        conversationContext.transcriptContext(noneText: AppText.none)
    }

    func recordTranscript(role: String, text: String, linkID: String? = nil) {
        conversationContext.appendTranscript(role: role, text: text, linkID: linkID)
    }

}
