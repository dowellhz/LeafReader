import Foundation

enum SpeechRuntimeBackendTests {
    static func testPiperWorkerInputLineNormalizesNewlines() throws {
        let line = PiperTTSBackend.workerInputLine(for: "  Hello\nPiper\rWorker  ")
        try expectEqual(
            String(data: line, encoding: .utf8),
            "Hello Piper Worker\n",
            "Piper worker input should be a single newline-terminated request line"
        )
    }

    static func testPiperWorkerOutputPathValidation() throws {
        let outputDirectory = URL(fileURLWithPath: "/tmp/leafreader-piper-worker", isDirectory: true)
        let valid = outputDirectory.appendingPathComponent("123.wav")
        try expectEqual(
            PiperTTSBackend.workerOutputURL(from: valid.path, outputDirectory: outputDirectory),
            valid,
            "Piper worker output should accept wav files in the worker output directory"
        )
        try expectEqual(
            PiperTTSBackend.workerOutputURL(from: "/tmp/other/123.wav", outputDirectory: outputDirectory),
            nil,
            "Piper worker output should reject paths outside the worker output directory"
        )
        try expectEqual(
            PiperTTSBackend.workerOutputURL(from: "not a path", outputDirectory: outputDirectory),
            nil,
            "Piper worker output should reject non-wav stdout lines"
        )
    }

    static func testPiperCoreMLFallbackDiagnostics() throws {
        try expect(
            PiperTTSBackend.shouldDisableCoreML(
                forDiagnostic: "Dynamic shape is not supported for now, for input:input"
            ),
            "Piper should disable CoreML after ONNX Runtime reports unsupported dynamic shapes"
        )
        try expect(
            PiperTTSBackend.shouldDisableCoreML(
                forDiagnostic: "CoreML does not support input dim > 16384"
            ),
            "Piper should disable CoreML after CoreML provider reports unsupported inputs"
        )
        try expect(
            !PiperTTSBackend.shouldDisableCoreML(forDiagnostic: "Loaded voice in 0.12 second(s)"),
            "normal Piper diagnostics should not disable CoreML"
        )
    }

    static func testPiperWorkerRestartThreshold() throws {
        try expect(
            !PiperTTSBackend.shouldRestartWorker(synthesisCount: 23, maxSynthesisCount: 24),
            "Piper worker should stay warm before the synthesis limit"
        )
        try expect(
            PiperTTSBackend.shouldRestartWorker(synthesisCount: 24, maxSynthesisCount: 24),
            "Piper worker should restart when it reaches the synthesis limit"
        )
        try expect(
            !PiperTTSBackend.shouldRestartWorker(synthesisCount: 100, maxSynthesisCount: 0),
            "Piper worker restart limit should be disabled when max is zero"
        )
    }

    static func testKokoroInstalledVoiceCacheKeyUsesVariantVoiceAndPath() throws {
        let first = KokoroVoiceResourceManager.installedVoiceCacheKey(
            voiceID: "af_heart",
            variant: "en",
            destination: URL(fileURLWithPath: "/tmp/kokoro/af_heart.bin")
        )
        let second = KokoroVoiceResourceManager.installedVoiceCacheKey(
            voiceID: "af_heart",
            variant: "zh",
            destination: URL(fileURLWithPath: "/tmp/kokoro/af_heart.bin")
        )
        let third = KokoroVoiceResourceManager.installedVoiceCacheKey(
            voiceID: "af_heart",
            variant: "en",
            destination: URL(fileURLWithPath: "/tmp/other/af_heart.bin")
        )
        try expect(first != second, "Kokoro voice cache should separate English and Chinese variants")
        try expect(first != third, "Kokoro voice cache should include the installed destination path")
        KokoroVoiceResourceManager.invalidateInstalledVoiceCache()
    }

    static func testVocabularyAudioCacheKeySeparatesSpeechSettings() throws {
        let first = VocabularyAudioCache.entry(text: "hello", runtimeID: "kitten", voiceID: "expr-voice-2-f", speedID: "normal")
        let second = VocabularyAudioCache.entry(text: "hello", runtimeID: "kitten", voiceID: "expr-voice-2-m", speedID: "normal")
        let third = VocabularyAudioCache.entry(text: "hello", runtimeID: "kitten", voiceID: "expr-voice-2-f", speedID: "settings-slow")
        let fourth = VocabularyAudioCache.entry(text: "hello", runtimeID: "piper", voiceID: "expr-voice-2-f", speedID: "normal")
        try expectEqual(VocabularyAudioCache.maximumBytes, 100 * 1024 * 1024, "vocabulary audio cache should stay capped at 100 MB")
        try expect(first.url != second.url, "vocabulary audio cache should separate voices")
        try expect(first.url != third.url, "vocabulary audio cache should separate speed settings")
        try expect(first.url != fourth.url, "vocabulary audio cache should separate runtimes")
    }
}
