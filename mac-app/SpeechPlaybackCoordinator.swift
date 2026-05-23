import Cocoa
import AVFoundation

final class SpeechPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlaybackCoordinator()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.SpeechPlayback.readingSegmentDidChange")
    private static let idleShutdownDelay: TimeInterval = 180
    private static let maxPendingReadAloudSegments = 2

    fileprivate let queue = DispatchQueue(label: "LeafReader.SpeechPlayback", qos: .userInitiated)
    fileprivate let kokoroBackend = KokoroTTSBackend()
    fileprivate let kittenBackend = KittenServerTTSBackend()
    fileprivate var activeBackend: PreferredBackend?
    private var currentPlayer: AVAudioPlayer?
    private var currentSegment: PlaybackSegment?
    private var pendingSegments: [PlaybackSegment] = []
    private var activeSpeechSegments: [ReadAloudSegment] = []
    private var activeGenerationID = UUID()
    private var isGeneratingSegments = false
    private var isPlaybackPaused = false
    private var isStoppingPlayback = false
    private var playbackFinishHandler: (() -> Void)?
    fileprivate var interruptionPlayer: AVAudioPlayer?
    fileprivate var interruptionOutputURL: URL?
    fileprivate var interruptionOutputShouldRemove = true
    fileprivate var interruptionFinishHandler: (() -> Void)?
    fileprivate var activeInterruptionGenerationID = UUID()
    private var idleShutdownWorkItem: DispatchWorkItem?
    private var playbackWatchdogWorkItem: DispatchWorkItem?
    fileprivate var interruptionWatchdogWorkItem: DispatchWorkItem?

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
                    pageIndex: segment.pageIndex
                )
            }
        }
        let combinedText = segments.map(\.speechText).joined(separator: " ")
        guard SpeechTextPolicy.isLocalTTSCandidate(combinedText), !segments.isEmpty else {
            completion(false)
            finished?()
            return
        }

        let generationID = UUID()
        beginGeneration(generationID, segments: segments, finished: finished)
        queue.async { [weak self] in
            guard let self else { return }
            var didReportSuccess = false
            var didGenerateAnySegment = false
            for (segmentIndex, segment) in segments.enumerated() {
                guard self.isActiveGeneration(generationID) else { return }
                guard self.waitForReadAloudBufferCapacity(generationID: generationID) else { return }
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LeafReader-SpeechPlayback-\(UUID().uuidString).wav")
                guard self.generateWAV(text: segment.speechText, outputURL: outputURL) else {
                    try? FileManager.default.removeItem(at: outputURL)
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
                        index: segmentIndex + 1,
                        total: segments.count,
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

    private func beginGeneration(_ generationID: UUID, segments: [ReadAloudSegment], finished: (() -> Void)?) {
        let work = {
            self.activeGenerationID = generationID
            self.activeSpeechSegments = segments
            self.isGeneratingSegments = true
            self.isPlaybackPaused = false
            self.playbackFinishHandler = finished
            self.stopAndClearPlayback()
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
            try? FileManager.default.removeItem(at: segment.outputURL)
            playNextOutputIfNeeded()
            return
        }
        player.delegate = self
        player.prepareToPlay()
        currentPlayer = player
        currentSegment = segment
        postReadingSegment(segment)
        if !player.play() {
            NSLog("LeafReader SpeechPlayback: AVAudioPlayer playback failed (output=%@)", segment.outputURL.path)
            try? FileManager.default.removeItem(at: segment.outputURL)
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
            try? FileManager.default.removeItem(at: currentSegment.outputURL)
        }
        player.delegate = nil
        currentPlayer = nil
        currentSegment = nil
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

    private func stopAndClearPlayback() {
        isStoppingPlayback = true
        let player = currentPlayer
        let segmentToRemove = currentSegment
        let pendingToRemove = pendingSegments
        playbackWatchdogWorkItem?.cancel()
        playbackWatchdogWorkItem = nil
        currentPlayer = nil
        currentSegment = nil
        pendingSegments.removeAll()
        player?.delegate = nil
        player?.stop()
        if let segmentToRemove {
            try? FileManager.default.removeItem(at: segmentToRemove.outputURL)
        }
        for segment in pendingToRemove {
            try? FileManager.default.removeItem(at: segment.outputURL)
        }
        isStoppingPlayback = false
        postReadingEnded()
    }

    private func forceTerminateRuntimeProcesses() {
        kokoroBackend.stop()
        kittenBackend.stop()
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
        }
    }

    func shutdownForTermination() {
        idleShutdownWorkItem?.cancel()
        idleShutdownWorkItem = nil
        stopAndClearPlayback()
        forceTerminateRuntimeProcesses()
    }

    fileprivate func cancelScheduledIdleShutdown() {
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

    fileprivate func generateWAV(text: String, outputURL: URL, voiceID: String? = nil) -> Bool {
        let backend = Self.preferredBackend(for: text)
        prepareForBackend(backend)
        switch backend {
        case .kokoroCoreML:
            return kokoroBackend.synthesize(text: text, outputURL: outputURL, voiceID: voiceID)
        case .kitten:
            return kittenBackend.synthesize(text: text, outputURL: outputURL, voiceID: voiceID)
        case .none:
            return false
        }
    }

    private func prepareForBackend(_ backend: PreferredBackend) {
        guard activeBackend != backend else { return }
        switch backend {
        case .kokoroCoreML:
            kittenBackend.stop()
        case .kitten:
            kokoroBackend.stop()
        case .none:
            stopRuntimeProcesses()
        }
        activeBackend = backend
    }

    private func stopRuntimeProcesses() {
        kokoroBackend.stop()
        kittenBackend.stop()
        activeBackend = nil
    }
}
