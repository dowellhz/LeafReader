import Foundation

struct SavedAIConversation: Codable {
    var bubbles: [SavedAIConversationBubble]

    static let empty = SavedAIConversation(bubbles: [])
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

    init(kind: Kind, index: Int, progress: Double?, selectedText: String? = nil, pdfBounds: [StoredPDFWordRect]? = nil) {
        self.kind = kind
        self.index = index
        self.progress = progress
        self.selectedText = selectedText
        self.pdfBounds = pdfBounds
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
