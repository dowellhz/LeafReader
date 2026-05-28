import Foundation

enum SelectionToolbarContextAction: Equatable {
    case addWord
    case summarize
}

enum SelectionToolbarDisplayMode: Equatable {
    case full(showsSpeak: Bool)
    case offlineWord
    case offlineCopyOnly
    case needsModelKeyWord
    case needsModelKeyCopyOnly
}

struct SelectionToolbarConfiguration: Equatable {
    let contextAction: SelectionToolbarContextAction
    let displayMode: SelectionToolbarDisplayMode

    static func make(
        isVocabularySelection: Bool,
        queryCapability: ReaderQueryCapability,
        shouldShowSpeakAction: Bool
    ) -> SelectionToolbarConfiguration {
        let contextAction: SelectionToolbarContextAction = isVocabularySelection ? .addWord : .summarize
        let displayMode: SelectionToolbarDisplayMode
        switch queryCapability {
        case .modelAvailable:
            displayMode = .full(showsSpeak: shouldShowSpeakAction)
        case .offlineDictionary:
            displayMode = isVocabularySelection ? .offlineWord : .offlineCopyOnly
        case .needsModelConfiguration:
            displayMode = isVocabularySelection ? .needsModelKeyWord : .needsModelKeyCopyOnly
        }
        return SelectionToolbarConfiguration(contextAction: contextAction, displayMode: displayMode)
    }
}
