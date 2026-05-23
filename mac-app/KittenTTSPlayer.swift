import Cocoa
import AVFoundation

final class KittenTTSPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = KittenTTSPlayer()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.KittenTTS.readingSegmentDidChange")
    private static let idleShutdownDelay: TimeInterval = 180
    private static let maxPendingReadAloudSegments = 2

    private enum Runtime {
        static let backendEnvironmentKey = "LEAFREADER_TTS_BACKEND"
    }

    private let queue = DispatchQueue(label: "LeafReader.KittenTTS", qos: .userInitiated)
    private let kokoroBackend = KokoroTTSBackend()
    private let kittenBackend = KittenServerTTSBackend()
    private var activeBackend: PreferredBackend?
    private var currentPlayer: AVAudioPlayer?
    private var currentSegment: PlaybackSegment?
    private var pendingSegments: [PlaybackSegment] = []
    private var activeSpeechSegments: [ReadAloudSegment] = []
    private var activeGenerationID = UUID()
    private var isGeneratingSegments = false
    private var isPlaybackPaused = false
    private var isStoppingPlayback = false
    private var playbackFinishHandler: (() -> Void)?
    private var interruptionPlayer: AVAudioPlayer?
    private var interruptionOutputURL: URL?
    private var interruptionOutputShouldRemove = true
    private var interruptionFinishHandler: (() -> Void)?
    private var activeInterruptionGenerationID = UUID()
    private var idleShutdownWorkItem: DispatchWorkItem?
    private var playbackWatchdogWorkItem: DispatchWorkItem?
    private var interruptionWatchdogWorkItem: DispatchWorkItem?

    private override init() {}

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

    private struct PlaybackSegment {
        let outputURL: URL
        let speechText: String
        let text: String
        let matchText: String
        let index: Int
        let total: Int
        let pageIndex: Int?
    }

    func speakEnglish(_ text: String, completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        let segments = SpeechTextPolicy.readAloudSegments(for: text).map {
            ReadAloudSegment(speechText: $0)
        }
        speakEnglish(segments: segments, completion: completion, finished: finished)
    }

    func speakEnglish(segments inputSegments: [ReadAloudSegment], completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
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
                    .appendingPathComponent("LeafReader-KittenTTS-\(UUID().uuidString).wav")
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
        NSLog("LeafReader KittenTTS: AVAudioPlayer decode error: %@", String(describing: error))
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

    func speakEnglishInterruption(_ text: String, completion: @escaping (Bool) -> Void, finished: @escaping () -> Void) {
        cancelScheduledIdleShutdown()
        let value = SpeechTextPolicy.normalizedReadAloudInput(text)
        guard SpeechTextPolicy.isLocalTTSCandidate(value) else {
            completion(false)
            return
        }

        let segment = SpeechTextPolicy.segments(for: value).joined(separator: " ")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-KittenTTS-Interrupt-\(UUID().uuidString).wav")
        let generationID = UUID()
        beginInterruptionGeneration(generationID)
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isActiveInterruptionGeneration(generationID) else {
                try? FileManager.default.removeItem(at: outputURL)
                return
            }
            guard self.generateWAV(text: segment, outputURL: outputURL) else {
                try? FileManager.default.removeItem(at: outputURL)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    completion(false)
                }
                return
            }
            DispatchQueue.main.async {
                guard self.activeInterruptionGenerationID == generationID else {
                    try? FileManager.default.removeItem(at: outputURL)
                    return
                }
                completion(true)
                self.playInterruptionOutput(outputURL, finished: finished)
            }
        }
    }

    func speakCachedPreviewInterruption(
        _ text: String,
        runtimeID: String,
        voiceID: String,
        speedID: String,
        completion: @escaping (Bool) -> Void,
        finished: @escaping () -> Void
    ) {
        cancelScheduledIdleShutdown()
        let value = SpeechTextPolicy.normalizedReadAloudInput(text)
        guard SpeechTextPolicy.isLocalTTSCandidate(value) else {
            completion(false)
            return
        }

        let segment = SpeechTextPolicy.segments(for: value).joined(separator: " ")
        let cacheURL = TTSPreviewCache.audioURL(text: segment, runtimeID: runtimeID, voiceID: voiceID, speedID: speedID)
        let generationID = UUID()
        beginInterruptionGeneration(generationID)
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isActiveInterruptionGeneration(generationID) else { return }
            if TTSWaveFile.isUsable(at: cacheURL) {
                NSLog("LeafReader TTS preview: cache hit runtime=%@ voice=%@ speed=%@ output=%@", runtimeID, voiceID, speedID, cacheURL.path)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    completion(true)
                    self.playInterruptionOutput(cacheURL, removeAfterPlayback: false, finished: finished)
                }
                return
            }

            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let tempURL = cacheURL.deletingLastPathComponent()
                .appendingPathComponent("pending-\(UUID().uuidString).wav")
            guard self.generateWAV(text: segment, outputURL: tempURL, voiceID: voiceID),
                  TTSWaveFile.isUsable(at: tempURL) else {
                NSLog("LeafReader TTS preview: generation failed runtime=%@ voice=%@ speed=%@ output=%@", runtimeID, voiceID, speedID, tempURL.path)
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    completion(false)
                }
                return
            }
            try? FileManager.default.removeItem(at: cacheURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: cacheURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    completion(false)
                }
                return
            }
            NSLog("LeafReader TTS preview: generated runtime=%@ voice=%@ speed=%@ output=%@", runtimeID, voiceID, speedID, cacheURL.path)
            DispatchQueue.main.async {
                guard self.activeInterruptionGenerationID == generationID else { return }
                completion(true)
                self.playInterruptionOutput(cacheURL, removeAfterPlayback: false, finished: finished)
            }
        }
    }

    func cancelCurrentSpeechPreview(terminateKokoroWorker: Bool = false) {
        beginInterruptionGeneration(UUID())
        guard terminateKokoroWorker else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.kokoroBackend.stop()
            if self.activeBackend == .kokoroCoreML {
                self.activeBackend = nil
            }
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
            NSLog("LeafReader KittenTTS: AVAudioPlayer load failed (output=%@, error=%@)", segment.outputURL.path, String(describing: error))
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
            NSLog("LeafReader KittenTTS: AVAudioPlayer playback failed (output=%@)", segment.outputURL.path)
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
                "LeafReader KittenTTS: playback watchdog advanced stuck segment (index=%d, total=%d, output=%@)",
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

    private func playInterruptionOutput(_ outputURL: URL, removeAfterPlayback: Bool = true, finished: @escaping () -> Void) {
        stopInterruptionPlayback()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: outputURL)
        } catch {
            NSLog("LeafReader KittenTTS: interruption AVAudioPlayer load failed (output=%@, error=%@)", outputURL.path, String(describing: error))
            try? FileManager.default.removeItem(at: outputURL)
            finished()
            return
        }
        interruptionPlayer = player
        interruptionOutputURL = outputURL
        interruptionOutputShouldRemove = removeAfterPlayback
        interruptionFinishHandler = finished
        player.delegate = self
        player.prepareToPlay()
        if !player.play() {
            NSLog("LeafReader KittenTTS: interruption AVAudioPlayer playback failed (output=%@)", outputURL.path)
            finishInterruptionPlayback()
        } else {
            NSLog("LeafReader TTS preview: playback started duration=%.3f output=%@", player.duration, outputURL.path)
            scheduleInterruptionWatchdog(for: player, outputURL: outputURL)
        }
    }

    private func scheduleInterruptionWatchdog(for player: AVAudioPlayer, outputURL: URL) {
        interruptionWatchdogWorkItem?.cancel()
        let timeout = max(2.0, player.duration + 1.5)
        let workItem = DispatchWorkItem { [weak self, weak player] in
            guard let self,
                  let player,
                  self.interruptionPlayer === player else {
                return
            }
            NSLog("LeafReader KittenTTS: interruption playback watchdog advanced stuck sound (output=%@)", outputURL.path)
            player.stop()
            self.finishInterruptionPlayback()
        }
        interruptionWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func stopInterruptionPlayback() {
        interruptionWatchdogWorkItem?.cancel()
        interruptionWatchdogWorkItem = nil
        interruptionFinishHandler = nil
        interruptionPlayer?.delegate = nil
        interruptionPlayer?.stop()
        clearInterruptionPlayback()
    }

    private func finishInterruptionPlayback() {
        interruptionWatchdogWorkItem?.cancel()
        interruptionWatchdogWorkItem = nil
        let handler = interruptionFinishHandler
        interruptionFinishHandler = nil
        clearInterruptionPlayback()
        handler?()
    }

    private func clearInterruptionPlayback() {
        interruptionPlayer?.delegate = nil
        interruptionPlayer = nil
        if interruptionOutputShouldRemove, let interruptionOutputURL {
            try? FileManager.default.removeItem(at: interruptionOutputURL)
        }
        interruptionOutputShouldRemove = true
        interruptionOutputURL = nil
    }

    private func beginInterruptionGeneration(_ generationID: UUID) {
        let work = {
            self.activeInterruptionGenerationID = generationID
            self.stopInterruptionPlayback()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func isActiveInterruptionGeneration(_ generationID: UUID) -> Bool {
        var active = false
        DispatchQueue.main.sync {
            active = self.activeInterruptionGenerationID == generationID
        }
        return active
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

    private func cancelScheduledIdleShutdown() {
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

    private func generateWAV(text: String, outputURL: URL, voiceID: String? = nil) -> Bool {
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

    private enum PreferredBackend {
        case kokoroCoreML
        case kitten
        case none

        init(runtime: SpeechRuntimeResourceManager.Runtime) {
            switch runtime {
            case .kokoro:
                self = .kokoroCoreML
            case .kitten:
                self = .kitten
            }
        }
    }

    private static func preferredBackend() -> PreferredBackend {
        preferredBackend(for: "")
    }

    private static func preferredBackend(for text: String) -> PreferredBackend {
        if SpeechTextPolicy.prefersChineseTTS(text) {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro) ? .kokoroCoreML : .none
        }
        let value = ProcessInfo.processInfo.environment[Runtime.backendEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "kitten", "kittentts", "kitten-tts", "rust":
            return .kitten
        case "kokoro", "kokoro-coreml", "coreml":
            return .kokoroCoreML
        default:
            switch SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) {
            case .kitten:
                return .kitten
            case .kokoro:
                return .kokoroCoreML
            case .none:
                return .none
            }
        }
    }

    private func stopRuntimeProcesses() {
        kokoroBackend.stop()
        kittenBackend.stop()
        activeBackend = nil
    }
}
