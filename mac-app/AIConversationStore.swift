import Foundation

struct SavedAIConversation: Codable {
    var bubbles: [SavedAIConversationBubble]

    static let empty = SavedAIConversation(bubbles: [])

    static func mergedForSave(
        loaded: SavedAIConversation?,
        visible: SavedAIConversation,
        maxBubbles: Int
    ) -> SavedAIConversation {
        guard let loaded, !loaded.bubbles.isEmpty else {
            return visible
        }

        var mergedBubbles = loaded.bubbles
        var existingKeys = Set(mergedBubbles.map(conversationBubbleKey))
        for bubble in visible.bubbles where !existingKeys.contains(conversationBubbleKey(bubble)) {
            mergedBubbles.append(bubble)
            existingKeys.insert(conversationBubbleKey(bubble))
        }
        if mergedBubbles.count > maxBubbles {
            mergedBubbles = Array(mergedBubbles.suffix(maxBubbles))
        }
        return SavedAIConversation(bubbles: mergedBubbles)
    }

    private static func conversationBubbleKey(_ bubble: SavedAIConversationBubble) -> String {
        "\(bubble.role)\u{1F}\(bubble.text)"
    }
}

struct SavedAIConversationBubble: Codable {
    let role: String
    let text: String
    let collapsible: Bool
    let renderMarkdown: Bool
    let sourceLocation: AIConversationSourceLocation?
}

struct AIConversationSourceLocation: Codable, Equatable {
    enum Kind: String, Codable {
        case pdfPage
        case webProgress
    }

    let kind: Kind
    let index: Int
    let progress: Double?
    var selectedText: String?
    var pdfBounds: [StoredPDFWordRect]?
    var webContext: String?

    init(kind: Kind, index: Int, progress: Double?, selectedText: String? = nil, pdfBounds: [StoredPDFWordRect]? = nil, webContext: String? = nil) {
        self.kind = kind
        self.index = index
        self.progress = progress
        self.selectedText = selectedText
        self.pdfBounds = pdfBounds
        self.webContext = webContext
    }
}

final class AIConversationStore {
    private let key: String
    private let defaults: UserDefaults

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.key = "aiConversation.\(fileMD5)"
        self.defaults = defaults
    }

    func load() -> SavedAIConversation {
        guard let data = defaults.data(forKey: key),
              let conversation = try? JSONDecoder().decode(SavedAIConversation.self, from: data) else {
            return .empty
        }
        return conversation
    }

    func save(_ conversation: SavedAIConversation) {
        guard !conversation.bubbles.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(conversation) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
