import Foundation

enum AIChatRequestFormat: Equatable {
    case openAICompatible
    case anthropicMessages
}

enum AIProviderCapability: Hashable {
    case chat
    case embedding
}

struct AIProviderDescriptor: Equatable {
    let id: String
    let displayName: String
    let capabilities: Set<AIProviderCapability>
    let chatRequestFormat: AIChatRequestFormat

    init(
        id: String,
        displayName: String,
        capabilities: Set<AIProviderCapability> = [.chat],
        chatRequestFormat: AIChatRequestFormat = .openAICompatible
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.chatRequestFormat = chatRequestFormat
    }

    static let deepseek = AIProviderDescriptor(
        id: "deepseek",
        displayName: "DeepSeek"
    )

    static let minimax = AIProviderDescriptor(
        id: "minimax",
        displayName: "MiniMax"
    )

    static let openAI = AIProviderDescriptor(
        id: "openai",
        displayName: "OpenAI"
    )

    static let claude = AIProviderDescriptor(
        id: "claude",
        displayName: "Claude",
        chatRequestFormat: .anthropicMessages
    )

    static let custom = AIProviderDescriptor(
        id: "custom",
        displayName: AppText.localized("其他", "Other")
    )

    static let remoteChatProviders: [AIProviderDescriptor] = [
        .deepseek,
        .minimax,
        .openAI,
        .claude,
        .custom
    ]

    static func descriptor(for id: String) -> AIProviderDescriptor {
        remoteChatProviders.first { $0.id == id }
            ?? AIProviderDescriptor(id: id, displayName: id)
    }

    static func embeddingProvider(id: String, displayName: String) -> AIProviderDescriptor {
        AIProviderDescriptor(
            id: id,
            displayName: displayName,
            capabilities: [.embedding],
            chatRequestFormat: .openAICompatible
        )
    }
}
