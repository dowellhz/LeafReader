import Cocoa
import AVFoundation

final class SpeechPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlaybackCoordinator()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.SpeechPlayback.readingSegmentDidChange")
    static let idleShutdownDelay: TimeInterval = 180
    static let maxPendingReadAloudSegments = 2
    static let maxRecentPlaybackWAVSegments = 2

    let queue = DispatchQueue(label: "LeafReader.SpeechPlayback", qos: .userInitiated)
    let kokoroBackend = KokoroTTSBackend()
    let kittenBackend = KittenServerTTSBackend()
    let piperBackend = PiperTTSBackend()
    var activeBackend: PreferredBackend?
    var currentPlayer: AVAudioPlayer?
    var currentSegment: PlaybackSegment?
    var pendingSegments: [PlaybackSegment] = []
    var recentPlaybackCache: [PlaybackSegment] = []
    var activeSpeechSegments: [ReadAloudSegment] = []
    var lastPlayedSegmentIndex = 0
    var activeGenerationID = UUID()
    var isGeneratingSegments = false
    var isPlaybackPaused = false
    var isStoppingPlayback = false
    var manualAdvanceEnabled = false
    var manualAdvanceSegmentsRemaining = 0
    var shouldPlayNextGeneratedSegmentImmediately = false
    var isSkippingCurrentSegment = false
    var playbackFinishHandler: (() -> Void)?
    var lastSynthesisError: SpeechSynthesisError?
    var interruptionPlayer: AVAudioPlayer?
    var interruptionOutputURL: URL?
    var interruptionOutputShouldRemove = true
    var interruptionFinishHandler: (() -> Void)?
    var activeInterruptionGenerationID = UUID()
    var idleShutdownWorkItem: DispatchWorkItem?
    private var playbackWatchdogWorkItem: DispatchWorkItem?
    var interruptionWatchdogWorkItem: DispatchWorkItem?

    private override init() {}

    func speakText(
        _ text: String,
        options: SynthesisOptions = .default,
        completion: @escaping (Bool) -> Void,
        finished: (() -> Void)? = nil
    ) {
        let segments = SpeechTextPolicy.readAloudSegments(for: text).map {
            ReadAloudSegment(speechText: $0)
        }
        speakText(segments: segments, options: options, completion: completion, finished: finished)
    }

    func speakText(
        segments inputSegments: [ReadAloudSegment],
        options: SynthesisOptions = .default,
        completion: @escaping (Bool) -> Void,
        finished: (() -> Void)? = nil
    ) {
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
                    matchRange: speechSegments.count == 1 ? segment.matchRange : nil,
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

        generateAndPlay(
            segments: segments,
            allSegments: segments,
            options: options,
            completion: completion,
            finished: finished
        )
    }

    func playNextOutputIfNeeded() {
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

    func finishCurrentPlaybackIfMatching(_ player: AVAudioPlayer) {
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

    func finishPlaybackIfIdle() {
        guard currentPlayer == nil, pendingSegments.isEmpty, !isGeneratingSegments else { return }
        postReadingEnded()
        let handler = playbackFinishHandler
        playbackFinishHandler = nil
        handler?()
        scheduleIdleShutdown()
    }

    func stopAndClearPlayback(
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

}
