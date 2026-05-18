import Cocoa

extension AIChatPanel {
    func loadSavedConversation(_ conversation: SavedAIConversation) {
        guard !conversation.bubbles.isEmpty else { return }
        isRestoringSavedConversation = true
        defer { isRestoringSavedConversation = false }

        var skipLegacyVocabularyAnswer = false
        for bubble in conversation.bubbles {
            if bubble.role == AppText.userRole, isVocabularyBubbleTitle(bubble.text) {
                skipLegacyVocabularyAnswer = true
                continue
            }
            if skipLegacyVocabularyAnswer, bubble.role == AppText.aiRole {
                skipLegacyVocabularyAnswer = false
                continue
            }
            skipLegacyVocabularyAnswer = false
            appendBubble(
                role: bubble.role,
                text: bubble.text,
                collapsible: bubble.collapsible,
                renderMarkdown: bubble.renderMarkdown,
                sourceLocation: bubble.sourceLocation
            )
            recordTranscript(role: bubble.role, text: bubble.text)
            if bubble.role == AppText.userRole {
                appendMessage(ChatMessage(role: "user", content: bubble.text))
            } else if bubble.role == AppText.aiRole {
                appendMessage(ChatMessage(role: "assistant", content: bubble.text))
            }
        }
    }

    func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        trimMessagesIfNeeded()
    }

    func trimMessagesIfNeeded() {
        guard messages.count > Self.maxContextMessages + 1 else { return }
        let systemMessage = messages.first { $0.role == "system" } ?? ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        let recentMessages = messages
            .filter { $0.role != "system" }
            .suffix(Self.maxContextMessages)
        messages = [systemMessage] + recentMessages
    }
}
