import Foundation

extension SpeechPlaybackCoordinator {
    enum ReadingSegmentUserInfoKey {
        static let active = "active"
        static let waitingForManualAdvance = "waitingForManualAdvance"
        static let index = "index"
        static let total = "total"
        static let text = "text"
        static let matchText = "matchText"
        static let matchRangeLocation = "matchRangeLocation"
        static let matchRangeLength = "matchRangeLength"
        static let pageIndex = "pageIndex"
    }

    static func readAloudSegments(for text: String) -> [String] {
        SpeechTextPolicy.readAloudSegments(for: text)
    }

    func postWaitingForManualAdvance() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: [
                ReadingSegmentUserInfoKey.active: true,
                ReadingSegmentUserInfoKey.waitingForManualAdvance: true
            ]
        )
    }

    func postReadingSegment(_ segment: PlaybackSegment) {
        var userInfo: [String: Any] = [
            ReadingSegmentUserInfoKey.active: true,
            ReadingSegmentUserInfoKey.index: segment.index,
            ReadingSegmentUserInfoKey.total: segment.total,
            ReadingSegmentUserInfoKey.text: segment.text,
            ReadingSegmentUserInfoKey.matchText: segment.matchText
        ]
        if let matchRange = segment.matchRange {
            userInfo[ReadingSegmentUserInfoKey.matchRangeLocation] = matchRange.location
            userInfo[ReadingSegmentUserInfoKey.matchRangeLength] = matchRange.length
        }
        if let pageIndex = segment.pageIndex {
            userInfo[ReadingSegmentUserInfoKey.pageIndex] = pageIndex
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
            userInfo: [ReadingSegmentUserInfoKey.active: false]
        )
    }
}
