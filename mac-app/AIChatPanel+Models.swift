import Foundation

extension AIChatPanel {
    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }

    struct BubbleMetadata {
        var role: String
        var text: String
        var renderMarkdown: Bool
        var collapsible: Bool
        var linkID: String?
        var sourceLocation: AIConversationSourceLocation?
        var regenerationRequest: RegenerationRequest?
    }

    struct FailedAIRequest {
        let messages: [ChatMessage]
        let linkID: String?
        let linkedQuestion: String?
        let fallbackAnswer: String?
        let answerSuffix: String?
    }

    struct RegenerationRequest {
        let messages: [ChatMessage]
        let fallbackAnswer: String?
        let answerSuffix: String?
    }
}
