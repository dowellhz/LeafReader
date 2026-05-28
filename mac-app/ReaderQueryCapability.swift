import Foundation

struct ReaderCapabilityState: Equatable {
    let isOnline: Bool
    let hasModelAPIKey: Bool
    let isLocalDictionaryInstalled: Bool

    var queryCapability: ReaderQueryCapability {
        ReaderQueryCapability.current(
            isOnline: isOnline,
            hasModelAPIKey: hasModelAPIKey
        )
    }

    static func make(
        isOnline: Bool,
        hasModelAPIKey: Bool,
        isLocalDictionaryInstalled: Bool
    ) -> ReaderCapabilityState {
        ReaderCapabilityState(
            isOnline: isOnline,
            hasModelAPIKey: hasModelAPIKey,
            isLocalDictionaryInstalled: isLocalDictionaryInstalled
        )
    }
}

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
