import Foundation

enum ReaderAIContextPolicy {
    static let summaryContentLimit = 6000
    static let translationContentLimit = 9000
    static let questionContentLimit = 5000
    static let combinedContextSuffixLimit = 6000
    static let nearbyPageExcerptLimit = 1200
    static let documentAgentCurrentPageLimit = 3500
    static let documentAgentNearbyTextLimit = 5000
    static let evidenceBubbleCount = 4
    static let evidenceBubbleTextLimit = 500

    static func prefix(_ text: String, limit: Int) -> String {
        String(text.prefix(limit))
    }

    static func suffix(_ text: String, limit: Int) -> String {
        String(text.suffix(limit))
    }
}
