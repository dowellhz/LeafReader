import Foundation

extension SpeechPlaybackCoordinator {
    struct ReadAloudSegment {
        let speechText: String
        let displayText: String
        let matchText: String
        let pageIndex: Int?

        init(speechText: String, displayText: String? = nil, matchText: String? = nil, pageIndex: Int? = nil) {
            self.speechText = speechText
            self.displayText = displayText ?? speechText
            self.matchText = matchText ?? displayText ?? speechText
            self.pageIndex = pageIndex
        }
    }
}
