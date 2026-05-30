import Foundation

extension SpeechPlaybackCoordinator {
    func stopSpeaking() {
        let work = {
            self.activeGenerationID = UUID()
            self.playbackFinishHandler = nil
            self.isGeneratingSegments = false
            self.isPlaybackPaused = false
            self.stopInterruptionPlayback()
            self.stopAndClearPlayback()
            self.scheduleIdleShutdown()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func pauseSpeaking() {
        let work = {
            guard !self.isPlaybackPaused else { return }
            self.isPlaybackPaused = true
            self.currentPlayer?.pause()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func resumeSpeaking() {
        let work = {
            guard self.isPlaybackPaused else { return }
            self.isPlaybackPaused = false
            if let currentPlayer = self.currentPlayer {
                _ = currentPlayer.play()
            } else {
                self.playNextOutputIfNeeded()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func setManualAdvanceEnabled(_ enabled: Bool) {
        let work = {
            self.manualAdvanceEnabled = enabled
            if !enabled {
                self.manualAdvanceSegmentsRemaining = 0
            }
            if !enabled, self.isPlaybackPaused, self.currentPlayer == nil {
                self.isPlaybackPaused = false
                self.playNextOutputIfNeeded()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func advanceToNextSegment() {
        let work = {
            self.shouldPlayNextGeneratedSegmentImmediately = true
            self.isSkippingCurrentSegment = self.currentPlayer != nil
            self.allowOneManualAdvanceSegmentIfNeeded()
            self.isPlaybackPaused = false
            if let player = self.currentPlayer {
                player.stop()
                self.finishCurrentPlaybackIfMatching(player)
            } else {
                self.playNextOutputIfNeeded()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func replayPreviousSegment() {
        let work = {
            guard !self.activeSpeechSegments.isEmpty else { return }
            let currentIndex = self.currentSegment?.index ?? self.lastPlayedSegmentIndex
            let targetOffset = max(0, currentIndex - 2)
            let replaySegments = Array(self.activeSpeechSegments.dropFirst(targetOffset))
            guard !replaySegments.isEmpty else { return }
            let finished = self.playbackFinishHandler
            let targetIndex = targetOffset + 1
            let cachedPrefix = self.cachedReplayPrefix(startingAt: targetIndex, through: currentIndex)
            if !cachedPrefix.isEmpty {
                let remainingOffset = targetOffset + cachedPrefix.count
                let remainingSegments = Array(self.activeSpeechSegments.dropFirst(remainingOffset))
                self.allowOneManualAdvanceSegmentIfNeeded()
                self.generateAndPlay(
                    segments: remainingSegments,
                    allSegments: self.activeSpeechSegments,
                    indexOffset: remainingOffset,
                    initialPlaybackSegments: cachedPrefix,
                    completion: { _ in },
                    finished: finished
                )
                return
            }
            self.allowOneManualAdvanceSegmentIfNeeded()
            self.generateAndPlay(
                segments: replaySegments,
                allSegments: self.activeSpeechSegments,
                indexOffset: targetOffset,
                completion: { _ in },
                finished: finished
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func replayCurrentSegment() {
        let work = {
            guard !self.activeSpeechSegments.isEmpty else { return }
            let currentIndex = self.currentSegment?.index ?? self.lastPlayedSegmentIndex
            guard currentIndex > 0 else { return }
            let targetOffset = currentIndex - 1
            let replaySegments = Array(self.activeSpeechSegments.dropFirst(targetOffset))
            guard !replaySegments.isEmpty else { return }
            let finished = self.playbackFinishHandler
            let cachedPrefix = self.cachedReplayPrefix(startingAt: currentIndex, through: currentIndex)
            if !cachedPrefix.isEmpty {
                let remainingOffset = targetOffset + cachedPrefix.count
                let remainingSegments = Array(self.activeSpeechSegments.dropFirst(remainingOffset))
                self.allowOneManualAdvanceSegmentIfNeeded()
                self.generateAndPlay(
                    segments: remainingSegments,
                    allSegments: self.activeSpeechSegments,
                    indexOffset: remainingOffset,
                    initialPlaybackSegments: cachedPrefix,
                    completion: { _ in },
                    finished: finished
                )
                return
            }
            self.allowOneManualAdvanceSegmentIfNeeded()
            self.generateAndPlay(
                segments: replaySegments,
                allSegments: self.activeSpeechSegments,
                indexOffset: targetOffset,
                completion: { _ in },
                finished: finished
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func hasActiveReadAloudWork() -> Bool {
        if Thread.isMainThread {
            return currentPlayer != nil || !pendingSegments.isEmpty || isGeneratingSegments
        }
        var active = false
        DispatchQueue.main.sync {
            active = self.currentPlayer != nil || !self.pendingSegments.isEmpty || self.isGeneratingSegments
        }
        return active
    }

    private func allowOneManualAdvanceSegmentIfNeeded() {
        guard manualAdvanceEnabled else { return }
        manualAdvanceSegmentsRemaining = 1
    }
}
