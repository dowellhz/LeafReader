import Foundation

extension SpeechPlaybackCoordinator {
    enum ReadAloudNavigationTarget {
        case current
        case next
        case previous
    }

    struct ReadAloudSegment {
        let speechText: String
        let displayText: String
        let matchText: String
        let pageIndex: Int?
        let speechLanguageHint: AISettingsStore.SpeechLanguageHint?

        init(
            speechText: String,
            displayText: String? = nil,
            matchText: String? = nil,
            pageIndex: Int? = nil,
            speechLanguageHint: AISettingsStore.SpeechLanguageHint? = nil
        ) {
            self.speechText = speechText
            self.displayText = displayText ?? speechText
            self.matchText = matchText ?? displayText ?? speechText
            self.pageIndex = pageIndex
            self.speechLanguageHint = speechLanguageHint
        }

        func withSpeechLanguageHint(_ hint: AISettingsStore.SpeechLanguageHint?) -> ReadAloudSegment {
            ReadAloudSegment(
                speechText: speechText,
                displayText: displayText,
                matchText: matchText,
                pageIndex: pageIndex,
                speechLanguageHint: hint
            )
        }
    }
}
