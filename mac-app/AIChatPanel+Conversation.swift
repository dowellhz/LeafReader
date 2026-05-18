import Cocoa

extension AIChatPanel {
    func loadSavedConversation(_ conversation: SavedAIConversation) {
        guard !conversation.bubbles.isEmpty else { return }
        isRestoringSavedConversation = true
        defer { isRestoringSavedConversation = false }

        var skipLegacyVocabularyAnswer = false
        let initialBubbles = conversation.bubbles.suffix(Self.maxInitialSavedConversationBubbles)
        for bubble in initialBubbles {
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

    func hasConversationSourceBubble(_ source: AIConversationSourceLocation) -> Bool {
        bubbleMetadataByID.values.contains { $0.sourceLocation == source }
    }

    @discardableResult
    func appendSavedConversationBubbles(for source: AIConversationSourceLocation, from conversation: SavedAIConversation) -> Bool {
        let matchingBubbles = conversation.bubbles.filter { $0.sourceLocation == source }
        guard !matchingBubbles.isEmpty else { return false }

        let existingBubbleKeys = Set(bubbleMetadataByID.values
            .filter { $0.sourceLocation == source }
            .map { conversationBubbleKey(role: $0.role, text: $0.text) })
        let missingBubbles = matchingBubbles.filter {
            !existingBubbleKeys.contains(conversationBubbleKey(role: $0.role, text: $0.text))
        }
        guard !missingBubbles.isEmpty else { return true }

        isRestoringSavedConversation = true
        defer { isRestoringSavedConversation = false }

        for bubble in missingBubbles {
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
        return true
    }

    private func conversationBubbleKey(role: String, text: String) -> String {
        "\(role)\u{1F}\(text)"
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
