import Foundation

extension SpeechPlaybackCoordinator {
    func cachedReplayPrefix(startingAt startIndex: Int, through endIndex: Int) -> [PlaybackSegment] {
        guard startIndex <= endIndex else { return [] }
        var segments: [PlaybackSegment] = []
        for index in startIndex...endIndex {
            if let currentSegment, currentSegment.index == index, playbackFileExists(for: currentSegment) {
                segments.append(currentSegment)
            } else if let cachedSegment = cachedPlaybackSegment(for: index) {
                segments.append(cachedSegment)
            } else {
                break
            }
        }
        return segments
    }

    func cacheCompletedPlaybackSegment(_ segment: PlaybackSegment) {
        guard playbackFileExists(for: segment) else { return }
        recentPlaybackCache.removeAll {
            $0.index == segment.index || $0.outputURL == segment.outputURL
        }
        recentPlaybackCache.append(segment)
        while recentPlaybackCache.count > Self.maxRecentPlaybackWAVSegments {
            let removed = recentPlaybackCache.removeFirst()
            removePlaybackFile(for: removed)
        }
    }

    func clearRecentPlaybackSegments(preserving preservedOutputURLs: Set<URL> = []) {
        for segment in recentPlaybackCache {
            removePlaybackFile(for: segment, preserving: preservedOutputURLs)
        }
        recentPlaybackCache.removeAll {
            !preservedOutputURLs.contains($0.outputURL)
        }
    }

    func discardPlaybackSegment(_ segment: PlaybackSegment) {
        recentPlaybackCache.removeAll { $0.outputURL == segment.outputURL }
        removePlaybackFile(for: segment)
    }

    func removePlaybackFile(for segment: PlaybackSegment, preserving preservedOutputURLs: Set<URL> = []) {
        guard !preservedOutputURLs.contains(segment.outputURL) else { return }
        try? FileManager.default.removeItem(at: segment.outputURL)
    }

    func playbackFileExists(for segment: PlaybackSegment) -> Bool {
        FileManager.default.fileExists(atPath: segment.outputURL.path)
    }

    private func cachedPlaybackSegment(for index: Int) -> PlaybackSegment? {
        recentPlaybackCache.first {
            $0.index == index && playbackFileExists(for: $0)
        }
    }
}
