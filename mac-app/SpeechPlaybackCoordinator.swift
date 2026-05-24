import Cocoa
import AVFoundation

final class SpeechPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlaybackCoordinator()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.SpeechPlayback.readingSegmentDidChange")
    private static let idleShutdownDelay: TimeInterval = 180
    private static let maxPendingReadAloudSegments = 2
    private static let maxRecentPlaybackWAVSegments = 2

    let queue = DispatchQueue(label: "LeafReader.SpeechPlayback", qos: .userInitiated)
    let kokoroBackend = KokoroTTSBackend()
    let kittenBackend = KittenServerTTSBackend()
    let piperBackend = PiperTTSBackend()
    var activeBackend: PreferredBackend?
    private var currentPlayer: AVAudioPlayer?
    private var currentSegment: PlaybackSegment?
    private var pendingSegments: [PlaybackSegment] = []
    private var recentPlaybackCache: [PlaybackSegment] = []
    private var activeSpeechSegments: [ReadAloudSegment] = []
    private var lastPlayedSegmentIndex = 0
    private var activeGenerationID = UUID()
    private var isGeneratingSegments = false
    private var isPlaybackPaused = false
    private var isStoppingPlayback = false
    private var manualAdvanceEnabled = false
    private var manualAdvanceSegmentsRemaining = 0
    private var shouldPlayNextGeneratedSegmentImmediately = false
    private var isSkippingCurrentSegment = false
    private var playbackFinishHandler: (() -> Void)?
    private var lastSynthesisError: SpeechSynthesisError?
    var interruptionPlayer: AVAudioPlayer?
    var interruptionOutputURL: URL?
    var interruptionOutputShouldRemove = true
    var interruptionFinishHandler: (() -> Void)?
    var activeInterruptionGenerationID = UUID()
    private var idleShutdownWorkItem: DispatchWorkItem?
    private var playbackWatchdogWorkItem: DispatchWorkItem?
    var interruptionWatchdogWorkItem: DispatchWorkItem?

    private override init() {}

    private struct PlaybackSegment {
        let outputURL: URL
        let speechText: String
        let text: String
        let matchText: String
        let index: Int
        let total: Int
        let pageIndex: Int?
    }

    func speakText(_ text: String, completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        let segments = SpeechTextPolicy.readAloudSegments(for: text).map {
            ReadAloudSegment(speechText: $0)
        }
        speakText(segments: segments, completion: completion, finished: finished)
    }

    func speakText(segments inputSegments: [ReadAloudSegment], completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        cancelScheduledIdleShutdown()
        let segments = inputSegments.flatMap { segment -> [ReadAloudSegment] in
            let speechText = SpeechTextPolicy.normalizedReadAloudInput(segment.speechText)
            guard !speechText.isEmpty else { return [] }
            let displayText = segment.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchText = segment.matchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let speechSegments = SpeechTextPolicy.segments(for: speechText)
            return speechSegments.map {
                ReadAloudSegment(
                    speechText: $0,
                    displayText: speechSegments.count == 1 && !displayText.isEmpty ? displayText : $0,
                    matchText: speechSegments.count == 1 && !matchText.isEmpty ? matchText : $0,
                    pageIndex: segment.pageIndex,
                    speechLanguageHint: segment.speechLanguageHint
                )
            }
        }
        let combinedText = segments.map(\.speechText).joined(separator: " ")
        guard SpeechTextPolicy.isLocalTTSCandidate(combinedText), !segments.isEmpty else {
            completion(false)
            finished?()
            return
        }

        generateAndPlay(segments: segments, allSegments: segments, completion: completion, finished: finished)
    }

    private func generateAndPlay(
        segments: [ReadAloudSegment],
        allSegments: [ReadAloudSegment],
        indexOffset: Int = 0,
        initialPlaybackSegments: [PlaybackSegment] = [],
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

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === interruptionPlayer {
            finishInterruptionPlayback()
            return
        }
        guard !isStoppingPlayback else { return }
        finishCurrentPlaybackIfMatching(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        NSLog("LeafReader SpeechPlayback: AVAudioPlayer decode error: %@", String(describing: error))
        if player === interruptionPlayer {
            finishInterruptionPlayback()
            return
        }
        guard !isStoppingPlayback else { return }
        finishCurrentPlaybackIfMatching(player)
    }

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

    private func playNextOutputIfNeeded() {
        guard !isPlaybackPaused else { return }
        guard currentPlayer == nil,
              !pendingSegments.isEmpty else {
            finishPlaybackIfIdle()
            return
        }
        let segment = pendingSegments.removeFirst()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: segment.outputURL)
        } catch {
            NSLog("LeafReader SpeechPlayback: AVAudioPlayer load failed (output=%@, error=%@)", segment.outputURL.path, String(describing: error))
            discardPlaybackSegment(segment)
            playNextOutputIfNeeded()
            return
        }
        player.delegate = self
        player.prepareToPlay()
        currentPlayer = player
        currentSegment = segment
        lastPlayedSegmentIndex = segment.index
        postReadingSegment(segment)
        if !player.play() {
            NSLog("LeafReader SpeechPlayback: AVAudioPlayer playback failed (output=%@)", segment.outputURL.path)
            discardPlaybackSegment(segment)
            currentPlayer = nil
            currentSegment = nil
            playNextOutputIfNeeded()
        } else {
            schedulePlaybackWatchdog(for: player, segment: segment)
        }
    }

    private func finishCurrentPlaybackIfMatching(_ player: AVAudioPlayer) {
        guard player === currentPlayer else { return }
        playbackWatchdogWorkItem?.cancel()
        playbackWatchdogWorkItem = nil
        if let currentSegment {
            cacheCompletedPlaybackSegment(currentSegment)
        }
        player.delegate = nil
        currentPlayer = nil
        currentSegment = nil
        let didSkipCurrentSegment = isSkippingCurrentSegment
        isSkippingCurrentSegment = false
        if manualAdvanceEnabled, manualAdvanceSegmentsRemaining > 0, !didSkipCurrentSegment {
            manualAdvanceSegmentsRemaining -= 1
        }
        let shouldPauseForManualMode = manualAdvanceEnabled
            && manualAdvanceSegmentsRemaining == 0
            && (!pendingSegments.isEmpty || isGeneratingSegments)
        if shouldPauseForManualMode {
            isPlaybackPaused = true
            postWaitingForManualAdvance()
            return
        }
        manualAdvanceSegmentsRemaining = 0
        shouldPlayNextGeneratedSegmentImmediately = false
        isSkippingCurrentSegment = false
        playNextOutputIfNeeded()
    }

    private func schedulePlaybackWatchdog(for player: AVAudioPlayer, segment: PlaybackSegment) {
        playbackWatchdogWorkItem?.cancel()
        let timeout = max(2.0, player.duration + 1.5)
        let workItem = DispatchWorkItem { [weak self, weak player] in
            guard let self,
                  let player,
                  self.currentPlayer === player else {
                return
            }
            NSLog(
                "LeafReader SpeechPlayback: playback watchdog advanced stuck segment (index=%d, total=%d, output=%@)",
                segment.index,
                segment.total,
                segment.outputURL.path
            )
            player.stop()
            self.finishCurrentPlaybackIfMatching(player)
        }
        playbackWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func finishPlaybackIfIdle() {
        guard currentPlayer == nil, pendingSegments.isEmpty, !isGeneratingSegments else { return }
        postReadingEnded()
        let handler = playbackFinishHandler
        playbackFinishHandler = nil
        handler?()
        scheduleIdleShutdown()
    }

    private func stopAndClearPlayback(
        preservingOutputURLs: Set<URL> = [],
        keepRecentPlaybackCache: Bool = false
    ) {
        isStoppingPlayback = true
        let player = currentPlayer
        let segmentToRemove = currentSegment
        let pendingToRemove = pendingSegments
        playbackWatchdogWorkItem?.cancel()
        playbackWatchdogWorkItem = nil
        currentPlayer = nil
        currentSegment = nil
        pendingSegments.removeAll()
        shouldPlayNextGeneratedSegmentImmediately = false
        isSkippingCurrentSegment = false
        player?.delegate = nil
        player?.stop()
        if let segmentToRemove {
            removePlaybackFile(for: segmentToRemove, preserving: preservingOutputURLs)
        }
        for segment in pendingToRemove {
            removePlaybackFile(for: segment, preserving: preservingOutputURLs)
        }
        if !keepRecentPlaybackCache {
            clearRecentPlaybackSegments(preserving: preservingOutputURLs)
        }
        isStoppingPlayback = false
        postReadingEnded()
    }

    private func cachedReplayPrefix(startingAt startIndex: Int, through endIndex: Int) -> [PlaybackSegment] {
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

    private func cachedPlaybackSegment(for index: Int) -> PlaybackSegment? {
        recentPlaybackCache.first {
            $0.index == index && playbackFileExists(for: $0)
        }
    }

    private func cacheCompletedPlaybackSegment(_ segment: PlaybackSegment) {
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

    private func clearRecentPlaybackSegments(preserving preservedOutputURLs: Set<URL> = []) {
        for segment in recentPlaybackCache {
            removePlaybackFile(for: segment, preserving: preservedOutputURLs)
        }
        recentPlaybackCache.removeAll {
            !preservedOutputURLs.contains($0.outputURL)
        }
    }

    private func discardPlaybackSegment(_ segment: PlaybackSegment) {
        recentPlaybackCache.removeAll { $0.outputURL == segment.outputURL }
        removePlaybackFile(for: segment)
    }

    private func removePlaybackFile(for segment: PlaybackSegment, preserving preservedOutputURLs: Set<URL> = []) {
        guard !preservedOutputURLs.contains(segment.outputURL) else { return }
        try? FileManager.default.removeItem(at: segment.outputURL)
    }

    private func playbackFileExists(for segment: PlaybackSegment) -> Bool {
        FileManager.default.fileExists(atPath: segment.outputURL.path)
    }

    private func postWaitingForManualAdvance() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: ["active": true, "waitingForManualAdvance": true]
        )
    }

    private func forceTerminateRuntimeProcesses() {
        kokoroBackend.stop()
        kittenBackend.stop()
        piperBackend.stop()
        activeBackend = nil
    }

    private func postReadingSegment(_ segment: PlaybackSegment) {
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

    static func readAloudSegments(for text: String) -> [String] {
        SpeechTextPolicy.readAloudSegments(for: text)
    }

    private func postReadingEnded() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: ["active": false]
        )
    }

    func shutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
        queue.async {
            self.forceTerminateRuntimeProcesses()
        }
        DispatchQueue.main.async {
            self.stopAndClearPlayback()
        }
    }

    func shutdownRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        let targetBackend = PreferredBackend(runtime: runtime)
        queue.async {
            guard self.activeBackend != targetBackend else {
                DispatchQueue.main.async {
                    self.shutdown()
                }
                return
            }
            switch targetBackend {
            case .kokoroCoreML:
                self.kokoroBackend.stop()
            case .kitten:
                self.kittenBackend.stop()
            case .piper:
                self.piperBackend.stop()
            case .none:
                break
            }
        }
    }

    func stopKokoroWorkerIfLanguageDiffers(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async {
            self.kokoroBackend.stopIfLanguageDiffers(from: trimmed)
            guard Self.preferredBackend(for: trimmed) == .kokoroCoreML else { return }
            self.kokoroBackend.prewarmIfNeeded(text: trimmed)
        }
    }

    func shutdownForTermination() {
        idleShutdownWorkItem?.cancel()
        idleShutdownWorkItem = nil
        stopAndClearPlayback()
        forceTerminateRuntimeProcesses()
    }

    func cancelScheduledIdleShutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
    }

    private func scheduleIdleShutdown() {
        idleShutdownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.forceTerminateRuntimeProcesses()
            }
        }
        idleShutdownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleShutdownDelay, execute: workItem)
    }

    func generateWAV(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        generateWAVResult(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint
        ).isSuccess
    }

    func consumeLastSynthesisError() -> SpeechSynthesisError? {
        if Thread.isMainThread {
            let error = lastSynthesisError
            lastSynthesisError = nil
            return error
        }
        var error: SpeechSynthesisError?
        DispatchQueue.main.sync {
            error = self.lastSynthesisError
            self.lastSynthesisError = nil
        }
        return error
    }

    func generateWAVResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil,
        recordFailure: Bool = true
    ) -> Result<Void, SpeechSynthesisError> {
        let backend = Self.preferredBackend(for: text, languageHint: languageHint)
        prepareForBackend(backend)
        let result: Result<Void, SpeechSynthesisError>
        let runtime = backend.runtime
        switch backend {
        case .kokoroCoreML:
            result = kokoroBackend.synthesizeResult(
                text: text,
                outputURL: outputURL,
                voiceID: voiceID,
                languageHint: languageHint
            )
        case .kitten:
            result = kittenBackend.synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID)
        case .piper:
            result = piperBackend.synthesizeResult(text: text, outputURL: outputURL, voiceID: voiceID)
        case .none:
            result = .failure(.unsupportedLanguage(AppText.localized("当前朗读引擎", "Selected speech runtime")))
        }
        switch result {
        case .success:
            if let runtime {
                SpeechRuntimeInferenceFailureStore.clear(for: runtime)
            }
        case .failure(let error):
            if recordFailure {
                recordSynthesisFailure(
                    error,
                    text: text,
                    outputURL: outputURL,
                    voiceID: voiceID,
                    languageHint: languageHint
                )
            }
        }
        return result
    }

    func recordSynthesisFailure(
        _ error: SpeechSynthesisError,
        text: String,
        outputURL: URL,
        voiceID: String?,
        languageHint: AISettingsStore.SpeechLanguageHint?,
        context: String = "readAloud"
    ) {
        let backend = Self.preferredBackend(for: text, languageHint: languageHint)
        let runtime = backend.runtime
        let effectiveVoiceID = runtime.map {
            voiceID ?? AISettingsStore.selectedSpeechVoiceID(runtimeID: $0.id)
        }
        if let runtime {
            SpeechRuntimeInferenceFailureStore.record(
                error,
                for: runtime,
                voiceID: effectiveVoiceID,
                context: context,
                text: text,
                outputURL: outputURL
            )
        }
        logSynthesisFailure(
            error,
            runtime: runtime,
            voiceID: effectiveVoiceID,
            text: text,
            outputURL: outputURL
        )
        DispatchQueue.main.async {
            self.lastSynthesisError = error
        }
    }

    private func logSynthesisFailure(
        _ error: SpeechSynthesisError,
        runtime: SpeechRuntimeResourceManager.Runtime?,
        voiceID: String?,
        text: String,
        outputURL: URL
    ) {
        NSLog(
            "LeafReader TTS inference failed runtime=%@ voice=%@ textLength=%d output=%@ error=%@",
            runtime?.id ?? "none",
            voiceID ?? "none",
            text.count,
            outputURL.path,
            error.localizedDescription
        )
    }

    private static func preferredBackend(
        for text: String,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> PreferredBackend {
        if languageHint == .chinese, SpeechRuntimeResourceManager.isRunnable(.kokoro) {
            return .kokoroCoreML
        }
        return preferredBackend(for: text)
    }

    private func prepareForBackend(_ backend: PreferredBackend) {
        guard activeBackend != backend else { return }
        switch backend {
        case .kokoroCoreML:
            kittenBackend.stop()
            piperBackend.stop()
        case .kitten:
            kokoroBackend.stop()
            piperBackend.stop()
        case .piper:
            kokoroBackend.stop()
            kittenBackend.stop()
        case .none:
            stopRuntimeProcesses()
        }
        activeBackend = backend
    }

    private func stopRuntimeProcesses() {
        kokoroBackend.stop()
        kittenBackend.stop()
        piperBackend.stop()
        activeBackend = nil
    }
}
