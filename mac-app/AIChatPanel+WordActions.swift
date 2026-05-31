import AVFoundation
import Cocoa

extension AIChatPanel {
    func isVocabularySelection(_ text: String) -> Bool {
        VocabularyTextPolicy.isVocabularySelection(text)
    }

    func shouldUseLocalDictionary(for text: String) -> Bool {
        isSingleEnglishWord(text)
    }

    func handleLocalDictionaryQuestion(_ text: String) -> Bool {
        guard shouldUseLocalDictionary(for: text) else { return false }
        speakSelectedWordIfNeeded(text)
        let selectedContext = onAskSelectedText?(text) ?? ""
        let answerRequest = AnswerProviderRequest(text: text, context: selectedContext, linkID: nil)
        guard let answer = localOnlyAnswerProvider().answer(for: answerRequest)?.answer else {
            return false
        }

        let wordRequest = WordQuestionRequest(text: text, selectedContext: selectedContext)
        let linkID = onSelectedWordQuestionStarted?(wordRequest)
        if let linkID, hasLinkedBubble(id: linkID) {
            clearSelectedText()
            scrollToLinkedBubble(id: linkID)
            return true
        }
        let displayedQuestion = vocabularyBubbleTitle(for: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true, linkID: linkID)
        recordTranscript(role: AppText.userRole, text: displayedQuestion, linkID: linkID)
        let answerBody = appendBubble(role: AppText.aiRole, text: answer, collapsible: false, renderMarkdown: true, linkID: linkID)
        recordTranscript(role: AppText.aiRole, text: answer, linkID: linkID)
        appendMessage(ChatMessage(role: "user", content: wordPrompt(for: text, context: selectedContext), linkID: linkID))
        appendMessage(ChatMessage(role: "assistant", content: answer, linkID: linkID))
        if let linkID {
            onLinkedAnswerCompleted?(linkID, displayedQuestion, answer)
        }
        scrollToDictionaryAnswer(answerBody)
        clearSelectedText()
        return true
    }

    func scrollToDictionaryAnswer(_ body: NSTextField) {
        guard let box = body.superview else { return }
        DispatchQueue.main.async { [weak self, weak box] in
            guard let self, let box else { return }
            self.scrollTranscriptToTop(of: box)
        }
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
        if VocabularyTextPolicy.shouldUseSystemTTSForShortSelection(text) {
            speechSynthesizer.speak(SpeechUtteranceFactory.utterance(for: text))
            return
        }
        SpeechPlaybackCoordinator.shared.speakText(text) { [weak self] didUseLocalTTS in
            guard !didUseLocalTTS else { return }
            self?.speechSynthesizer.speak(SpeechUtteranceFactory.utterance(for: text))
        }
    }

    func wordPrompt(for word: String, context: String) -> String {
        AIPromptStore.wordPrompt(for: word, context: context)
    }

    func sentencePrompt(for text: String) -> String {
        AIPromptStore.sentencePrompt(for: text)
    }
}
