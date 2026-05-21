import Cocoa

final class KittenTTSPlayer: NSObject, NSSoundDelegate {
    static let shared = KittenTTSPlayer()
    static let readingSegmentDidChangeNotification = Notification.Name("LeafReader.KittenTTS.readingSegmentDidChange")
    private static let idleShutdownDelay: TimeInterval = 180

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
        static let maxSentenceLength = 520
        static let maxMergedSegmentLength = 420
        static let minSegmentWordCount = 18
    }

    private let queue = DispatchQueue(label: "LeafReader.KittenTTS", qos: .userInitiated)
    private var serverProcess: Process?
    private var serverOutputPipe: Pipe?
    private var serverErrorPipe: Pipe?
    private var kokoroWorkerProcess: Process?
    private var kokoroWorkerInputPipe: Pipe?
    private var kokoroWorkerOutputPipe: Pipe?
    private var kokoroWorkerErrorPipe: Pipe?
    private var currentSound: NSSound?
    private var currentSegment: PlaybackSegment?
    private var pendingSegments: [PlaybackSegment] = []
    private var activeSpeechSegments: [ReadAloudSegment] = []
    private var activeGenerationID = UUID()
    private var isGeneratingSegments = false
    private var isPlaybackPaused = false
    private var isStoppingPlayback = false
    private var playbackFinishHandler: (() -> Void)?
    private var interruptionSound: NSSound?
    private var interruptionOutputURL: URL?
    private var interruptionFinishHandler: (() -> Void)?
    private var idleShutdownWorkItem: DispatchWorkItem?

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

    private struct KokoroWorkerRequest: Codable {
        let id: String
        let text: String
        let output: String
        let voice: String?
        let speed: Double?
    }

    private struct KokoroWorkerResponse: Codable {
        let id: String
        let ok: Bool
        let error: String?
    }

    func warmUp() {
        cancelScheduledIdleShutdown()
        queue.async {
            switch Self.preferredBackend() {
            case .kokoroCoreML:
                if !self.ensureKokoroWorker() {
                    _ = self.ensureServer()
                }
            case .kitten:
                _ = self.ensureServer()
            }
        }
    }

    func speakEnglish(_ text: String, completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        let value = Self.normalizedEnglishTTSInput(text)
        let segments = Self.ttsSegments(for: value).map {
            ReadAloudSegment(speechText: $0)
        }
        speakEnglish(segments: segments, completion: completion, finished: finished)
    }

    func speakEnglish(segments inputSegments: [ReadAloudSegment], completion: @escaping (Bool) -> Void, finished: (() -> Void)? = nil) {
        cancelScheduledIdleShutdown()
        let segments = inputSegments.compactMap { segment -> ReadAloudSegment? in
            let speechText = Self.normalizedEnglishTTSInput(segment.speechText)
            guard !speechText.isEmpty else { return nil }
            let displayText = segment.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReadAloudSegment(
                speechText: speechText,
                displayText: displayText.isEmpty ? speechText : displayText,
                pageIndex: segment.pageIndex
            )
        }
        let combinedText = segments.map(\.speechText).joined(separator: " ")
        guard Self.isEnglishCandidate(combinedText), !segments.isEmpty else {
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

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if sound === interruptionSound {
            finishInterruptionPlayback()
            return
        }
        guard !isStoppingPlayback, sound === currentSound else { return }
        if let currentSegment {
            try? FileManager.default.removeItem(at: currentSegment.outputURL)
        }
        sound.delegate = nil
        currentSound = nil
        currentSegment = nil
        playNextOutputIfNeeded()
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
        let value = Self.normalizedEnglishTTSInput(text)
        guard Self.isEnglishCandidate(value) else {
            completion(false)
            return
        }

        let segment = Self.ttsSegments(for: value).joined(separator: " ")
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
            _ = self.currentSound?.pause()
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
            if let currentSound = self.currentSound {
                _ = currentSound.resume()
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
                  self.currentSound != nil else { return }
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
            return currentSound != nil || !pendingSegments.isEmpty || isGeneratingSegments
        }
        var active = false
        DispatchQueue.main.sync {
            active = self.currentSound != nil || !self.pendingSegments.isEmpty || self.isGeneratingSegments
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
        guard currentSound == nil,
              !pendingSegments.isEmpty else {
            finishPlaybackIfIdle()
            return
        }
        let segment = pendingSegments.removeFirst()
        guard let sound = NSSound(contentsOf: segment.outputURL, byReference: false) else {
            try? FileManager.default.removeItem(at: segment.outputURL)
            playNextOutputIfNeeded()
            return
        }
        sound.delegate = self
        currentSound = sound
        currentSegment = segment
        postReadingSegment(segment)
        if !sound.play() {
            try? FileManager.default.removeItem(at: segment.outputURL)
            currentSound = nil
            currentSegment = nil
            playNextOutputIfNeeded()
        }
    }

    private func finishPlaybackIfIdle() {
        guard currentSound == nil, pendingSegments.isEmpty, !isGeneratingSegments else { return }
        postReadingEnded()
        let handler = playbackFinishHandler
        playbackFinishHandler = nil
        handler?()
        scheduleIdleShutdown()
    }

    private func stopAndClearPlayback() {
        isStoppingPlayback = true
        let sound = currentSound
        let segmentToRemove = currentSegment
        let pendingToRemove = pendingSegments
        currentSound = nil
        currentSegment = nil
        pendingSegments.removeAll()
        sound?.delegate = nil
        sound?.stop()
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
        guard let sound = NSSound(contentsOf: outputURL, byReference: false) else {
            try? FileManager.default.removeItem(at: outputURL)
            finished()
            return
        }
        interruptionSound = sound
        interruptionOutputURL = outputURL
        interruptionFinishHandler = finished
        sound.delegate = self
        if !sound.play() {
            finishInterruptionPlayback()
        }
    }

    private func stopInterruptionPlayback() {
        interruptionFinishHandler = nil
        interruptionSound?.delegate = nil
        interruptionSound?.stop()
        clearInterruptionPlayback()
    }

    private func finishInterruptionPlayback() {
        let handler = interruptionFinishHandler
        interruptionFinishHandler = nil
        clearInterruptionPlayback()
        handler?()
    }

    private func clearInterruptionPlayback() {
        interruptionSound?.delegate = nil
        interruptionSound = nil
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
        ttsSegments(for: normalizedEnglishTTSInput(text))
    }

    private func postReadingEnded() {
        NotificationCenter.default.post(
            name: Self.readingSegmentDidChangeNotification,
            object: self,
            userInfo: ["active": false]
        )
    }

    private static func ttsSegments(for text: String) -> [String] {
        var sentenceUnits: [String] = []
        var current = ""
        func flushCurrent() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                sentenceUnits.append(contentsOf: splitLongSentence(value))
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if ".!?".contains(character) {
                flushCurrent()
            }
        }
        flushCurrent()

        return mergedShortSegments(sentenceUnits.isEmpty ? [text] : sentenceUnits)
    }

    private static func mergedShortSegments(_ segments: [String]) -> [String] {
        var merged: [String] = []
        var current = ""
        var currentWordCount = 0
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let candidate = current.isEmpty ? trimmed : "\(current) \(trimmed)"
            if !current.isEmpty, candidate.count > Runtime.maxMergedSegmentLength {
                merged.append(current)
                current = trimmed
                currentWordCount = wordCount(in: trimmed)
            } else {
                current = candidate
                currentWordCount += wordCount(in: trimmed)
            }

            if currentWordCount >= Runtime.minSegmentWordCount {
                merged.append(current)
                current = ""
                currentWordCount = 0
            }
        }
        if !current.isEmpty {
            if let last = merged.last,
               "\(last) \(current)".count <= Runtime.maxMergedSegmentLength {
                merged[merged.count - 1] = "\(last) \(current)"
            } else {
                merged.append(current)
            }
        }
        return merged
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func normalizedEnglishTTSInput(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
        value = value.replacingOccurrences(
            of: #"(?i)([A-Za-z])-\s*[\r\n]+\s*([A-Za-z])"#,
            with: "$1$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"([A-Za-z])\s*'\s*([A-Za-z])"#,
            with: "$1'$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(^|[\r\n]+|[.!?]\s+|["']\s*)([B-HJ-Zb-hj-z])\s+([a-z]{2,})"#,
            with: "$1$2$3",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[\r\n\t]+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        guard sentence.count > Runtime.maxSentenceLength else {
            return [sentence]
        }

        var segments: [String] = []
        var current = ""
        for word in sentence.split(separator: " ") {
            let next = current.isEmpty ? String(word) : "\(current) \(word)"
            if next.count > Runtime.maxSentenceLength, !current.isEmpty {
                segments.append(current)
                current = String(word)
            } else {
                current = next
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments.isEmpty ? [sentence] : segments
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
        switch Self.preferredBackend() {
        case .kokoroCoreML:
            stopKittenServer()
            if generateWAVWithKokoroWorker(text: text, outputURL: outputURL) {
                return true
            }
            if Self.generateWAVWithKokoroCoreML(text: text, outputURL: outputURL) {
                return true
            }
            return false
        case .kitten:
            stopKokoroWorker()
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
        }
    }

    private enum PreferredBackend {
        case kokoroCoreML
        case kitten
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
            switch SpeechRuntimeResourceManager.installedRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) {
            case .kitten:
                return .kitten
            case .kokoro, .none:
                return .kokoroCoreML
            }
        }
    }

    private static func generateWAVWithKokoroCoreML(text: String, outputURL: URL) -> Bool {
        guard let cliURL = kokoroCoreMLRuntime() else { return false }

        let process = Process()
        process.executableURL = cliURL
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let arguments = [
            "tts",
            text,
            "--backend",
            "kokoro",
            "--variant",
            "15s",
            "--voice",
            ProcessInfo.processInfo.environment[Runtime.kokoroCoreMLVoiceEnvironmentKey]
                ?? Runtime.defaultKokoroCoreMLVoice,
            "--output",
            outputURL.path
        ]
        process.arguments = arguments
        let diagnosticURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil)
        let diagnosticHandle = FileHandle(forWritingAtPath: diagnosticURL.path)
        process.standardOutput = diagnosticHandle
        process.standardError = diagnosticHandle
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            diagnosticHandle?.closeFile()
            try? FileManager.default.removeItem(at: diagnosticURL)
            NSLog("LeafReader Kokoro CoreML: failed to run FluidAudio CLI (error=%@)", error.localizedDescription)
            return false
        }
        diagnosticHandle?.closeFile()
        let outputExists = Self.isUsableWAV(at: outputURL)
        if process.terminationStatus == 0, outputExists {
            try? FileManager.default.removeItem(at: diagnosticURL)
            return true
        }

        if outputExists {
            try? FileManager.default.removeItem(at: diagnosticURL)
            NSLog(
                "LeafReader Kokoro CoreML: FluidAudio CLI exited with status=%d after creating audio; continuing playback (output=%@)",
                process.terminationStatus,
                outputURL.path
            )
            return true
        }

        let diagnosticData = (try? Data(contentsOf: diagnosticURL)) ?? Data()
        let message = Self.diagnosticTail(String(data: diagnosticData, encoding: .utf8))
        try? FileManager.default.removeItem(at: diagnosticURL)
        NSLog(
            "LeafReader Kokoro CoreML: FluidAudio CLI failed (status=%d, outputExists=%@, output=%@, details=%@)",
            process.terminationStatus,
            outputExists ? "yes" : "no",
            outputURL.path,
            message
        )
        return false
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

        let decoder = JSONDecoder()
        while let line = readWorkerLine(from: outputPipe.fileHandleForReading) {
            guard let data = line.data(using: .utf8),
                  let response = try? decoder.decode(KokoroWorkerResponse.self, from: data) else {
                continue
            }
            guard response.id == request.id else { continue }
            if response.ok, Self.isUsableWAV(at: outputURL) {
                return true
            }
            if let error = response.error, !error.isEmpty {
                NSLog("LeafReader Kokoro CoreML: worker synthesis failed (%@)", error)
            }
            return false
        }

        stopKokoroWorker()
        return false
    }

    private func ensureKokoroWorker() -> Bool {
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
            "15s",
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

    private func readWorkerLine(from handle: FileHandle) -> String? {
        var data = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty {
                return data.isEmpty ? nil : String(data: data, encoding: .utf8)
            }
            if byte[0] == 0x0A {
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            data.append(byte)
        }
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

    private static func isEnglishCandidate(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }
        return !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }
    private func ensureServer() -> Bool {
        guard let runtime = Self.rustRuntime() else { return false }
        if Self.isServerHealthy() {
            return true
        }
        if serverProcess?.isRunning == true {
            return waitForServer()
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = runtime.serverURL
        process.arguments = [
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
        } catch {
            NSLog("LeafReader KittenTTS: failed to start rust server (error=%@)", error.localizedDescription)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return false
        }

        serverProcess = process
        serverOutputPipe = outputPipe
        serverErrorPipe = errorPipe
        return waitForServer()
    }

    private func waitForServer() -> Bool {
        for _ in 0..<40 {
            if Self.isServerHealthy() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private static func isServerHealthy() -> Bool {
        var request = URLRequest(url: serverURL(path: "/v1/models"))
        request.timeoutInterval = 0.5
        let result = performRequest(request)
        return result.statusCode == 200
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
            NSLog(
                "LeafReader KittenTTS: server synthesis failed (status=%d, bytes=%d)",
                result.statusCode,
                result.data?.count ?? 0
            )
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

    private static func performRequest(_ request: URLRequest) -> (statusCode: Int, data: Data?) {
        let semaphore = DispatchSemaphore(value: 0)
        var statusCode = 0
        var responseData: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            responseData = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + request.timeoutInterval + 1)
        return (statusCode, responseData)
    }

    private static func serverURL(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(serverPort())\(path)")!
    }

    private static func serverPort() -> Int {
        let value = ProcessInfo.processInfo.environment[Runtime.portEnvironmentKey]
            .flatMap(Int.init) ?? Runtime.defaultPort
        return (1...65535).contains(value) ? value : Runtime.defaultPort
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
