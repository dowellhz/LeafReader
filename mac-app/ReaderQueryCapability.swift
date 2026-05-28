import Foundation

enum ReaderQueryCapability: Equatable {
    case modelAvailable
    case offlineDictionary
    case needsModelConfiguration

    static func current(
        isOnline: Bool,
        hasModelAPIKey: Bool
    ) -> ReaderQueryCapability {
        guard isOnline else { return .offlineDictionary }
        guard hasModelAPIKey else { return .needsModelConfiguration }
        return .modelAvailable
    }
}
