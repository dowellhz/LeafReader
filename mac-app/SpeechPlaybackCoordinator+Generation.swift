import Foundation

extension SpeechPlaybackCoordinator {
    func generateAndPlay(
        segments: [ReadAloudSegment],
        allSegments: [ReadAloudSegment],
        indexOffset: Int = 0,
        initialPlaybackSegments: [PlaybackSegment] = [],
        options: SynthesisOptions = .default,
        completion: @escaping (Bool) -> Void,
        finished: (() -> Void)?
    ) {
        let generationID = UUID()
        beginGeneration(
            generationID,
            allSegments: allSegments,
            indexOffset: indexOffset,
            preservingOutputURLs: Set(initialPlaybackSegments.map(\.outputURL)),
            keepRecentPlaybackCache: !initialPlaybackSegments.isEmpty,
            finished: finished
        )
        if !initialPlaybackSegments.isEmpty {
            pendingSegments.append(contentsOf: initialPlaybackSegments)
            playNextOutputIfNeeded()
            completion(true)
        }
        queue.async { [weak self] in
            guard let self else { return }
            var didReportSuccess = !initialPlaybackSegments.isEmpty
            var didGenerateAnySegment = false
            for (segmentIndex, segment) in segments.enumerated() {
                guard self.isActiveGeneration(generationID) else { return }
                guard self.waitForReadAloudBufferCapacity(generationID: generationID) else { return }
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LeafReader-SpeechPlayback-\(UUID().uuidString).wav")
                let result = self.generateWAVResult(
                    text: segment.speechText,
                    outputURL: outputURL,
                    languageHint: segment.speechLanguageHint,
                    options: options,
                    recordFailure: false
                )
                guard result.isSuccess else {
                    try? FileManager.default.removeItem(at: outputURL)
                    if self.isActiveGeneration(generationID),
                       case .failure(let error) = result {
                        self.recordSynthesisFailure(
                            error,
                            text: segment.speechText,
                            outputURL: outputURL,
                            voiceID: nil,
                            languageHint: segment.speechLanguageHint
                        )
                    }
                    continue
                }
                guard self.isActiveGeneration(generationID) else {
                    try? FileManager.default.removeItem(at: outputURL)
                    return
                }
                didGenerateAnySegment = true
                let shouldReportSuccess = !didReportSuccess
                if shouldReportSuccess {
                    didReportSuccess = true
                }
                DispatchQueue.main.async {
                    guard self.activeGenerationID == generationID else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return
                    }
                    self.enqueueSegment(PlaybackSegment(
                        outputURL: outputURL,
                        speechText: segment.speechText,
                        text: segment.displayText,
                        matchText: segment.matchText,
                        matchRange: segment.matchRange,
                        index: segmentIndex + 1 + indexOffset,
                        total: allSegments.count,
                        pageIndex: segment.pageIndex
                    ))
                    if shouldReportSuccess {
                        completion(true)
                    }
                }
            }
            DispatchQueue.main.async {
                guard self.activeGenerationID == generationID else {
                    return
                }
                self.isGeneratingSegments = false
                if !didGenerateAnySegment, !didReportSuccess {
                    completion(false)
                    self.finishPlaybackIfIdle()
                } else {
                    self.playNextOutputIfNeeded()
                }
            }
        }
    }

    private func beginGeneration(
        _ generationID: UUID,
        allSegments: [ReadAloudSegment],
        indexOffset: Int,
        preservingOutputURLs: Set<URL> = [],
        keepRecentPlaybackCache: Bool = false,
        finished: (() -> Void)?
    ) {
        let work = {
            self.activeGenerationID = generationID
            self.activeSpeechSegments = allSegments
            self.isGeneratingSegments = true
            self.isPlaybackPaused = false
            self.lastPlayedSegmentIndex = indexOffset
            self.playbackFinishHandler = finished
            self.stopAndClearPlayback(
                preservingOutputURLs: preservingOutputURLs,
                keepRecentPlaybackCache: keepRecentPlaybackCache
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func isActiveGeneration(_ generationID: UUID) -> Bool {
        if Thread.isMainThread {
            return activeGenerationID == generationID
        }
        var active = false
        DispatchQueue.main.sync {
            active = self.activeGenerationID == generationID
        }
        return active
    }

    private func waitForReadAloudBufferCapacity(generationID: UUID) -> Bool {
        while isActiveGeneration(generationID) {
            var pendingCount = 0
            DispatchQueue.main.sync {
                pendingCount = self.pendingSegments.count
            }
            if pendingCount < Self.maxPendingReadAloudSegments {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func enqueueSegment(_ segment: PlaybackSegment) {
        pendingSegments.append(segment)
        if shouldPlayNextGeneratedSegmentImmediately, currentPlayer == nil {
            shouldPlayNextGeneratedSegmentImmediately = false
            isPlaybackPaused = false
            playNextOutputIfNeeded()
            return
        }
        if manualAdvanceEnabled, isPlaybackPaused, currentPlayer == nil {
            postWaitingForManualAdvance()
            return
        }
        playNextOutputIfNeeded()
    }
}
