import Foundation

extension SpeechPlaybackCoordinator {
    static func readAloudSegments(for text: String) -> [String] {
        SpeechTextPolicy.readAloudSegments(for: text)
    }

    func postWaitingForManualAdvance() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: ["active": true, "waitingForManualAdvance": true]
        )
    }

    func postReadingSegment(_ segment: PlaybackSegment) {
        var userInfo: [String: Any] = [
            "active": true,
            "index": segment.index,
            "total": segment.total,
            "text": segment.text,
            "matchText": segment.matchText
        ]
        if let pageIndex = segment.pageIndex {
            userInfo["pageIndex"] = pageIndex
        }
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: userInfo
        )
    }

    func postReadingEnded() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: ["active": false]
        )
    }
}
