import Cocoa
import AVFoundation

final class KittenTTSPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = KittenTTSPlayer()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.KittenTTS.readingSegmentDidChange")
    private static let idleShutdownDelay: TimeInterval = 180
    private static let processServerPort = Int.random(in: 20000...49151)
    private static let kokoroWorkerResponseTimeout: TimeInterval = 45
    private static let kokoroFallbackTimeout: TimeInterval = 45

    private enum Runtime {
        static let backendEnvironmentKey = "LEAFREADER_TTS_BACKEND"
        static let kokoroCoreMLCLIEnvironmentKey = "LEAFREADER_KOKORO_COREML_CLI"
        static let kokoroCoreMLVoiceEnvironmentKey = "LEAFREADER_KOKORO_COREML_VOICE"
        static let kokoroCoreMLSpeedEnvironmentKey = "LEAFREADER_KOKORO_COREML_SPEED"
        static let modelEnvironmentKey = "LEAFREADER_KITTENTTS_RS_MODEL"
        static let voiceEnvironmentKey = "LEAFREADER_KITTENTTS_VOICE"
        static let speedEnvironmentKey = "LEAFREADER_KITTENTTS_SPEED"
        static let portEnvironmentKey = "LEAFREADER_KITTENTTS_RS_PORT"
        static let defaultKokoroCoreMLVoice = "af_heart"
        static let defaultKokoroCoreMLCLIPath = ".local/share/leafreader/kokoro-coreml/fluidaudiocli"
        static let defaultVoice = "Jasper"
        static let defaultSpeed = 1.0
        static let defaultPort = 18181
        static let defaultServerPath = ".local/share/leafreader/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
        static let defaultModelPath = ".local/share/leafreader/kittentts-rs-runtime/kitten-tts-mini"
    }

    private let queue = DispatchQueue(label: "LeafReader.KittenTTS", qos: .userInitiated)
    private var serverProcess: Process?
    private var serverOutputPipe: Pipe?
    private var serverErrorPipe: Pipe?
    private var activeBackend: PreferredBackend?
    private var kokoroWorkerProcess: Process?
    private var kokoroWorkerInputPipe: Pipe?
    private var kokoroWorkerOutputPipe: Pipe?
    private var kokoroWorkerErrorPipe: Pipe?
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
    private var interruptionFinishHandler: (() -> Void)?
    private var idleShutdownWorkItem: DispatchWorkItem?
    private var playbackWatchdogWorkItem: DispatchWorkItem?
    private var interruptionWatchdogWorkItem: DispatchWorkItem?

    private override init() {}

    struct ReadAloudSegment {
        let speechText: String
        let displayText: String
        let pageIndex: Int?

        init(speechText: String, displayText: String? = nil, pageIndex: Int? = nil) {
            self.speechText = speechText
            self.displayText = displayText ?? speechText
            self.pageIndex = pageIndex
        }
    }

    private struct PlaybackSegment {
        let outputURL: URL
        let speechText: String
        let text: String
        let index: Int
        let total: Int
        let pageIndex: Int?
    }

    private struct ServerHealthCheck {
        let isHealthy: Bool
        let statusCode: Int
        let timedOut: Bool
        let hasModelResponse: Bool

        var failureDescription: String {
            if timedOut {
                return "timeout"
            }
            if statusCode != 200 {
                return "status=\(statusCode)"
            }
            return hasModelResponse ? "unknown" : "invalid model response"
        }
    }

    private struct KokoroWorkerRequest: Codable {
        let id: String
        let text: String
        let output: String
        let voice: String?
        let speed: Double?
    }

    func speakEnglish(_ text: String, completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        let segments = SpeechTextPolicy.readAloudSegments(for: text).map {
            ReadAloudSegment(speechText: $0)
        }
        speakEnglish(segments: segments, completion: completion, finished: finished)
    }

    func speakEnglish(segments inputSegments: [ReadAloudSegment], completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        cancelScheduledIdleShutdown()
        let segments = inputSegments.compactMap { segment -> ReadAloudSegment? in
            let speechText = SpeechTextPolicy.normalizedEnglishInput(segment.speechText)
            guard !speechText.isEmpty else { return nil }
            let displayText = segment.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReadAloudSegment(
                speechText: speechText,
                displayText: displayText.isEmpty ? speechText : displayText,
                pageIndex: segment.pageIndex
            )
        }
        let combinedText = segments.map(\.speechText).joined(separator: " ")
        guard SpeechTextPolicy.isEnglishCandidate(combinedText), !segments.isEmpty else {
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
        let value = SpeechTextPolicy.normalizedEnglishInput(text)
        guard SpeechTextPolicy.isEnglishCandidate(value) else {
            completion(false)
            return
        }

        let segment = SpeechTextPolicy.segments(for: value).joined(separator: " ")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-KittenTTS-Interrupt-\(UUID().uuidString).wav")
        queue.async { [weak self] in
            guard let self else { return }
            guard self.generateWAV(text: segment, outputURL: outputURL) else {
                try? FileManager.default.removeItem(at: outputURL)
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            DispatchQueue.main.async {
                completion(true)
                self.playInterruptionOutput(outputURL, finished: finished)
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

    func regenerateRemainingSegmentsForUpdatedParameters() {
        let work = {
            guard let segment = self.currentSegment,
                  self.currentPlayer != nil else { return }
            let generationID = UUID()
            let oldPendingSegments = self.pendingSegments
            let startIndex = max(0, segment.index)
            let sourceSegments = startIndex < self.activeSpeechSegments.count
                ? Array(self.activeSpeechSegments[startIndex...])
                : []
            let totalSegments = self.activeSpeechSegments.count

            self.activeGenerationID = generationID
            self.pendingSegments.removeAll()
            for pending in oldPendingSegments {
                try? FileManager.default.removeItem(at: pending.outputURL)
            }
            guard !sourceSegments.isEmpty else {
                self.isGeneratingSegments = false
                return
            }
            self.isGeneratingSegments = true

            self.queue.async { [weak self] in
                guard let self else { return }
                var generatedAny = false
                for (offset, sourceSegment) in sourceSegments.enumerated() {
                    guard self.isActiveGeneration(generationID) else { return }
                    let outputURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("LeafReader-KittenTTS-Refresh-\(UUID().uuidString).wav")
                    guard self.generateWAV(text: sourceSegment.speechText, outputURL: outputURL) else {
                        try? FileManager.default.removeItem(at: outputURL)
                        continue
                    }
                    guard self.isActiveGeneration(generationID) else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return
                    }
                    generatedAny = true
                    let playbackSegment = PlaybackSegment(
                        outputURL: outputURL,
                        speechText: sourceSegment.speechText,
                        text: sourceSegment.displayText,
                        index: startIndex + offset + 1,
                        total: totalSegments,
                        pageIndex: sourceSegment.pageIndex
                    )
                    DispatchQueue.main.async {
                        guard self.activeGenerationID == generationID else {
                            try? FileManager.default.removeItem(at: outputURL)
                            return
                        }
                        self.enqueueSegment(playbackSegment)
                    }
                }
                DispatchQueue.main.async {
                    guard self.activeGenerationID == generationID else { return }
                    self.isGeneratingSegments = false
                    if generatedAny {
                        self.playNextOutputIfNeeded()
                    } else {
                        self.finishPlaybackIfIdle()
                    }
                }
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

    private func playInterruptionOutput(_ outputURL: URL, finished: @escaping () -> Void) {
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
        interruptionFinishHandler = finished
        player.delegate = self
        player.prepareToPlay()
        if !player.play() {
            NSLog("LeafReader KittenTTS: interruption AVAudioPlayer playback failed (output=%@)", outputURL.path)
            finishInterruptionPlayback()
        } else {
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
        if let interruptionOutputURL {
            try? FileManager.default.removeItem(at: interruptionOutputURL)
        }
        interruptionOutputURL = nil
    }

    private func forceTerminateRuntimeProcesses() {
        kokoroWorkerErrorPipe?.fileHandleForReading.readabilityHandler = nil
        serverOutputPipe?.fileHandleForReading.readabilityHandler = nil
        serverErrorPipe?.fileHandleForReading.readabilityHandler = nil
        try? kokoroWorkerInputPipe?.fileHandleForWriting.close()
        try? kokoroWorkerOutputPipe?.fileHandleForReading.close()
        if kokoroWorkerProcess?.isRunning == true {
            kokoroWorkerProcess?.terminate()
        }
        if serverProcess?.isRunning == true {
            serverProcess?.terminate()
        }
        kokoroWorkerProcess = nil
        kokoroWorkerInputPipe = nil
        kokoroWorkerOutputPipe = nil
        kokoroWorkerErrorPipe = nil
        serverProcess = nil
        serverOutputPipe = nil
        serverErrorPipe = nil
        activeBackend = nil
    }

    private func stopKittenServer() {
        serverOutputPipe?.fileHandleForReading.readabilityHandler = nil
        serverErrorPipe?.fileHandleForReading.readabilityHandler = nil
        if serverProcess?.isRunning == true {
            serverProcess?.terminate()
        }
        serverProcess = nil
        serverOutputPipe = nil
        serverErrorPipe = nil
    }

    private func postReadingSegment(_ segment: PlaybackSegment) {
        var userInfo: [String: Any] = [
            "active": true,
            "index": segment.index,
            "total": segment.total,
            "text": segment.text
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
                self.stopKokoroWorker()
            case .kitten:
                self.stopKittenServer()
            case .none:
                break
            }
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

    private func generateWAV(text: String, outputURL: URL) -> Bool {
        let backend = Self.preferredBackend()
        prepareForBackend(backend)
        switch backend {
        case .kokoroCoreML:
            if generateWAVWithKokoroWorker(text: text, outputURL: outputURL) {
                return true
            }
            if Self.generateWAVWithKokoroCoreML(text: text, outputURL: outputURL) {
                return true
            }
            return false
        case .kitten:
            if ensureServer() {
                if Self.generateWAVWithServer(text: text, outputURL: outputURL) {
                    return true
                }
                stopKittenServer()
                if ensureServer(),
                   Self.generateWAVWithServer(text: text, outputURL: outputURL) {
                    return true
                }
            }
            return false
        case .none:
            return false
        }
    }

    private func prepareForBackend(_ backend: PreferredBackend) {
        guard activeBackend != backend else { return }
        switch backend {
        case .kokoroCoreML:
            stopKittenServer()
        case .kitten:
            stopKokoroWorker()
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

    private static func generateWAVWithKokoroCoreML(text: String, outputURL: URL) -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        guard let cliURL = kokoroCoreMLRuntime() else { return false }

        let arguments = [
            "tts",
            text,
            "--backend",
            "kokoro-ane",
            "--variant",
            "en",
            "--voice",
            ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLVoiceEnvironmentKey]
                ?? Runtime.defaultKokoroCoreMLVoice,
            "--speed",
            String(Self.kokoroTTSSpeed()),
            "--output",
            outputURL.path
        ]

        let result: ProcessRunResult
        do {
            result = try ProcessRunner.run(
                executableURL: cliURL,
                arguments: arguments,
                timeout: kokoroFallbackTimeout,
                currentDirectoryURL: FileManager.default.temporaryDirectory
            )
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to run FluidAudio CLI (error=%@)", error.localizedDescription)
            return false
        }
        if result.timedOut {
            NSLog("LeafReader Kokoro CoreML: FluidAudio CLI timed out after %.0fs", kokoroFallbackTimeout)
            return false
        }
        let outputExists = Self.isUsableWAV(at: outputURL)
        if result.terminationStatus == 0, outputExists {
            return true
        }

        if outputExists {
            NSLog(
                "LeafReader Kokoro CoreML: FluidAudio CLI exited with status=%d after creating audio; continuing playback (output=%@)",
                result.terminationStatus,
                outputURL.path
            )
            return true
        }

        let message = Self.diagnosticTail(processOutputText(stdout: result.stdout, stderr: result.stderr))
        NSLog(
            "LeafReader Kokoro CoreML: FluidAudio CLI failed (status=%d, outputExists=%@, output=%@, details=%@)",
            result.terminationStatus,
            outputExists ? "yes" : "no",
            outputURL.path,
            message
        )
        return false
    }

    private static func processOutputText(stdout: Data, stderr: Data) -> String {
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""
        return [stdoutText, stderrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func diagnosticTail(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.count > 2400 else { return text }
        return String(text.suffix(2400))
    }

    private static func isUsableWAV(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 44
    }

    private func generateWAVWithKokoroWorker(text: String, outputURL: URL) -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else {
            stopKokoroWorker()
            return false
        }
        guard ensureKokoroWorker(),
              let inputPipe = kokoroWorkerInputPipe,
              let outputPipe = kokoroWorkerOutputPipe else {
            return false
        }

        let request = KokoroWorkerRequest(
            id: UUID().uuidString,
            text: text,
            output: outputURL.path,
            voice: ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLVoiceEnvironmentKey]
                ?? Runtime.defaultKokoroCoreMLVoice,
            speed: Self.kokoroTTSSpeed()
        )
        guard let requestData = try? JSONEncoder().encode(request) else {
            return false
        }

        do {
            var line = requestData
            line.append(0x0A)
            try inputPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to write worker request (error=%@)", error.localizedDescription)
            stopKokoroWorker()
            return false
        }

        guard let response = readKokoroWorkerResponse(
            requestID: request.id,
            from: outputPipe.fileHandleForReading,
            timeout: Self.kokoroWorkerResponseTimeout
        ) else {
            NSLog("LeafReader Kokoro CoreML: worker synthesis timed out")
            stopKokoroWorker()
            return false
        }
        if response.ok, Self.isUsableWAV(at: outputURL) {
            return true
        }
        if let error = response.error, !error.isEmpty {
            NSLog("LeafReader Kokoro CoreML: worker synthesis failed (%@)", error)
        }
        return false
    }

    private func ensureKokoroWorker() -> Bool {
        guard SpeechRuntimeResourceManager.isRunnable(.kokoro) else { return false }
        if kokoroWorkerProcess?.isRunning == true {
            return true
        }
        stopKokoroWorker()
        guard let cliURL = Self.kokoroCoreMLRuntime() else { return false }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = cliURL
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.arguments = [
            "tts-worker",
            "--variant",
            "en",
            "--voice",
            ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLVoiceEnvironmentKey]
                ?? Runtime.defaultKokoroCoreMLVoice
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            NSLog("LeafReader Kokoro CoreML: failed to start worker (error=%@)", error.localizedDescription)
            return false
        }
        kokoroWorkerProcess = process
        kokoroWorkerInputPipe = inputPipe
        kokoroWorkerOutputPipe = outputPipe
        kokoroWorkerErrorPipe = errorPipe
        return true
    }

    private func stopKokoroWorker() {
        kokoroWorkerErrorPipe?.fileHandleForReading.readabilityHandler = nil
        kokoroWorkerInputPipe?.fileHandleForWriting.closeFile()
        if kokoroWorkerProcess?.isRunning == true {
            kokoroWorkerProcess?.terminate()
        }
        kokoroWorkerProcess = nil
        kokoroWorkerInputPipe = nil
        kokoroWorkerOutputPipe = nil
        kokoroWorkerErrorPipe = nil
    }

    private func stopRuntimeProcesses() {
        stopKokoroWorker()
        stopKittenServer()
        activeBackend = nil
    }

    private func readKokoroWorkerResponse(
        requestID: String,
        from handle: FileHandle,
        timeout: TimeInterval
    ) -> KokoroWorkerResponse? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var reader = KokoroWorkerResponseReader(requestID: requestID)
        var matchedResponse: KokoroWorkerResponse?
        var didComplete = false

        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return }
            guard !data.isEmpty else {
                didComplete = true
                semaphore.signal()
                return
            }

            if let response = reader.append(data) {
                matchedResponse = response
                didComplete = true
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        handle.readabilityHandler = nil

        lock.lock()
        defer { lock.unlock() }
        if waitResult == .timedOut {
            didComplete = true
        }
        return matchedResponse
    }

    private static func kokoroCoreMLRuntime() -> URL? {
        let fileManager = FileManager.default
        let environmentPath = ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLCLIEnvironmentKey]
        let candidatePaths = [
            environmentPath,
            Bundle.main.resourceURL?
                .appendingPathComponent("SpeechRuntimes", isDirectory: true)
                .appendingPathComponent("kokoro-coreml", isDirectory: true)
                .appendingPathComponent("fluidaudiocli")
                .path,
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(Runtime.defaultKokoroCoreMLCLIPath)
                .path,
        ].compactMap { $0 }

        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func ensureServer() -> Bool {
        guard let runtime = Self.rustRuntime() else { return false }
        if Self.serverHealthCheck().isHealthy {
            return true
        }
        if serverProcess?.isRunning == true {
            return waitForServer()
        }

        let arguments = [
            runtime.modelDirectoryURL.path,
            "--host",
            "127.0.0.1",
            "--port",
            String(Self.serverPort())
        ]
        var environment = ProcessInfo.processInfo.environment
        if let espeakRuntime = Self.bundledESpeakRuntime() {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(espeakRuntime.binDirectoryURL.path):\(existingPath)"
            environment["ESPEAK_DATA_PATH"] = espeakRuntime.dataDirectoryURL.path
        }
        guard let started = startDrainedProcess(
            executableURL: runtime.serverURL,
            arguments: arguments,
            environment: environment
        ) else {
            return false
        }

        serverProcess = started.process
        serverOutputPipe = started.outputPipe
        serverErrorPipe = started.errorPipe
        return waitForServer()
    }

    private func startDrainedProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) -> (process: Process, outputPipe: Pipe, errorPipe: Pipe)? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        do {
            try process.run()
            return (process, outputPipe, errorPipe)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            NSLog("LeafReader KittenTTS: failed to start process %@ (error=%@)", executableURL.path, error.localizedDescription)
            return nil
        }
    }

    private func waitForServer() -> Bool {
        var lastCheck = Self.serverHealthCheck()
        if lastCheck.isHealthy {
            return true
        }
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.2)
            lastCheck = Self.serverHealthCheck()
            if lastCheck.isHealthy {
                return true
            }
        }
        NSLog("LeafReader KittenTTS: server did not become healthy (%@, port=%d)", lastCheck.failureDescription, Self.serverPort())
        return false
    }

    private static func serverHealthCheck() -> ServerHealthCheck {
        var request = URLRequest(url: serverURL(path: "/v1/models"))
        request.timeoutInterval = 0.5
        let result = performRequest(request)
        let hasModelResponse = isKittenServerModelsResponse(result.data)
        return ServerHealthCheck(
            isHealthy: !result.timedOut && result.statusCode == 200 && hasModelResponse,
            statusCode: result.statusCode,
            timedOut: result.timedOut,
            hasModelResponse: hasModelResponse
        )
    }

    private static func isKittenServerModelsResponse(_ data: Data?) -> Bool {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return jsonContainsKittenTTSModel(json)
    }

    private static func jsonContainsKittenTTSModel(_ value: Any) -> Bool {
        if let string = value as? String {
            let normalized = string.lowercased()
            return normalized.contains("kitten") && normalized.contains("tts")
        }
        if let array = value as? [Any] {
            return array.contains { jsonContainsKittenTTSModel($0) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { jsonContainsKittenTTSModel($0) }
        }
        return false
    }

    private static func generateWAVWithServer(text: String, outputURL: URL) -> Bool {
        var request = URLRequest(url: serverURL(path: "/v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": "kitten-tts",
            "input": text,
            "voice": ProcessInfo.processInfo.environment[Runtime.voiceEnvironmentKey] ?? Runtime.defaultVoice,
            "speed": ttsSpeed(),
            "response_format": "wav"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return false
        }
        request.httpBody = body

        let result = performRequest(request)
        guard result.statusCode == 200,
              let data = result.data,
              !data.isEmpty else {
            if result.timedOut {
                NSLog("LeafReader KittenTTS: server synthesis timed out (port=%d)", serverPort())
            } else {
                NSLog(
                    "LeafReader KittenTTS: server synthesis failed (status=%d, bytes=%d, port=%d)",
                    result.statusCode,
                    result.data?.count ?? 0,
                    serverPort()
                )
            }
            return false
        }
        do {
            try data.write(to: outputURL, options: .atomic)
            return true
        } catch {
            NSLog("LeafReader KittenTTS: failed to write server audio (error=%@)", error.localizedDescription)
            return false
        }
    }

    private static func performRequest(_ request: URLRequest) -> (statusCode: Int, data: Data?, timedOut: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var statusCode = 0
        var responseData: Data?
        var didFinish = false
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            responseData = data
            semaphore.signal()
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + request.timeoutInterval + 1)
        if waitResult == .timedOut {
            lock.lock()
            didFinish = true
            lock.unlock()
            task.cancel()
            return (statusCode, responseData, true)
        }
        return (statusCode, responseData, false)
    }

    private static func serverURL(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(serverPort())\(path)")!
    }

    private static func serverPort() -> Int {
        if let value = ProcessInfo.processInfo.environment[Runtime.portEnvironmentKey].flatMap(Int.init),
           (1...65535).contains(value) {
            return value
        }
        return processServerPort
    }

    private static func ttsSpeed() -> Double {
        let value = ProcessInfo.processInfo.environment[Runtime.speedEnvironmentKey]
            .flatMap(Double.init) ?? AISettingsStore.kittenSpeechSpeedMultiplier
        return min(max(value, 0.5), 2.0)
    }

    private static func bundledESpeakRuntime() -> (binDirectoryURL: URL, dataDirectoryURL: URL)? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let runtimeRoot = resourceURL
            .appendingPathComponent("SpeechRuntimes", isDirectory: true)
            .appendingPathComponent("espeak-ng", isDirectory: true)
        let binDirectoryURL = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
        let executableURL = binDirectoryURL.appendingPathComponent("espeak-ng")
        let dataDirectoryURL = runtimeRoot
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("espeak-ng-data", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.fileExists(atPath: dataDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return (binDirectoryURL, dataDirectoryURL)
    }

    private static func kokoroTTSSpeed() -> Double {
        let value = ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLSpeedEnvironmentKey]
            .flatMap(Double.init) ?? AISettingsStore.kokoroSpeechSpeedMultiplier
        return min(max(value, 0.5), 2.0)
    }

    private static func rustRuntime() -> (serverURL: URL, modelDirectoryURL: URL)? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        if let modelPath = environment[Runtime.modelEnvironmentKey] {
            let serverPath = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(Runtime.defaultServerPath)
                .path
            guard fileManager.isExecutableFile(atPath: serverPath),
                  fileManager.fileExists(atPath: modelPath) else {
                return nil
            }
            return (URL(fileURLWithPath: serverPath), URL(fileURLWithPath: modelPath))
        }

        let runtime = SpeechRuntimeResourceManager.Runtime.kitten
        let serverCandidateRoots = [runtime.bundledInstallDirectory, runtime.installDirectory].compactMap { $0 }
        let modelCandidateRoots = [runtime.installDirectory, runtime.bundledInstallDirectory].compactMap { $0 }
        for runtimeRoot in serverCandidateRoots {
            let serverURL = runtimeRoot.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
            guard fileManager.isExecutableFile(atPath: serverURL.path) else {
                continue
            }
            for modelRoot in modelCandidateRoots {
                let modelDirectoryURL = modelRoot.appendingPathComponent("kitten-tts-mini", isDirectory: true)
                let modelURL = modelDirectoryURL.appendingPathComponent("kitten_tts_mini_v0_8.onnx")
                let voicesURL = modelDirectoryURL.appendingPathComponent("voices.npz")
                let configURL = modelDirectoryURL.appendingPathComponent("config.json")
                guard fileManager.fileExists(atPath: modelURL.path),
                      fileManager.fileExists(atPath: voicesURL.path),
                      fileManager.fileExists(atPath: configURL.path) else {
                    continue
                }
                return (serverURL, modelDirectoryURL)
            }
        }
        return nil
    }
}
