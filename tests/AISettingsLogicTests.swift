import Foundation

private struct EmbeddingEndpointOption {
    let id: String
    let endpoint: String
    let defaultModel: String
    let requiresAPIKey: Bool
    let payloadExtras: [String: String]

    init(id: String, endpoint: String, defaultModel: String, requiresAPIKey: Bool = true, payloadExtras: [String: String] = [:]) {
        self.id = id
        self.endpoint = endpoint
        self.defaultModel = defaultModel
        self.requiresAPIKey = requiresAPIKey
        self.payloadExtras = payloadExtras
    }
}

private let embeddingOptions = [
    EmbeddingEndpointOption(id: "openai", endpoint: "https://api.openai.com/v1/embeddings", defaultModel: "text-embedding-3-small"),
    EmbeddingEndpointOption(id: "siliconflow", endpoint: "https://api.siliconflow.cn/v1/embeddings", defaultModel: "Qwen/Qwen3-Embedding-8B", payloadExtras: ["encoding_format": "float"]),
    EmbeddingEndpointOption(id: "ollama", endpoint: "http://127.0.0.1:11434/api/embed", defaultModel: "nomic-embed-text", requiresAPIKey: false),
    EmbeddingEndpointOption(id: "other", endpoint: "", defaultModel: "")
]

private func selectedEmbeddingOption(savedEndpoint: String) -> EmbeddingEndpointOption {
    if let option = embeddingOptions.first(where: { $0.endpoint == savedEndpoint }) {
        return option
    }
    if savedEndpoint == "https://api.siliconflow.com/v1/embeddings" {
        return embeddingOptions.first { $0.id == "siliconflow" }!
    }
    let requiresKey = !(URL(string: savedEndpoint)?.isLocalEndpoint ?? false)
    return EmbeddingEndpointOption(id: "other", endpoint: savedEndpoint, defaultModel: "", requiresAPIKey: requiresKey)
}

private func embeddingModelName(savedModel: String, savedEndpoint: String) -> String {
    if !savedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return savedModel
    }
    let defaultModel = selectedEmbeddingOption(savedEndpoint: savedEndpoint).defaultModel
    return defaultModel.isEmpty ? "text-embedding-3-small" : defaultModel
}

private func embeddingPayload(option: EmbeddingEndpointOption, model: String, input: [String]) -> [String: Any] {
    var payload: [String: Any] = ["model": model, "input": input]
    for (key, value) in option.payloadExtras {
        payload[key] = value
    }
    return payload
}

private struct EmbeddingKeyStore {
    var encryptedKeys: [String: String] = [:]
    var legacyPlainKeys: [String: String] = [:]

    mutating func saveEmbeddingKey(_ key: String, optionID: String) {
        let storageKey = encryptedProviderKey(for: optionID)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            encryptedKeys.removeValue(forKey: storageKey)
        } else {
            encryptedKeys[storageKey] = trimmed
        }
        legacyPlainKeys.removeValue(forKey: "apiKey.embedding")
    }

    func embeddingKey(for optionID: String) -> String {
        encryptedKeys[encryptedProviderKey(for: optionID)] ?? ""
    }

    mutating func embeddingKeyMigratingLegacyIfNeeded(for optionID: String) -> String {
        let storageKey = encryptedProviderKey(for: optionID)
        if let key = encryptedKeys[storageKey], !key.isEmpty {
            return key
        }
        if let legacyEncrypted = encryptedKeys["encryptedApiKey.embedding"], !legacyEncrypted.isEmpty {
            encryptedKeys[storageKey] = legacyEncrypted
            encryptedKeys.removeValue(forKey: "encryptedApiKey.embedding")
            return legacyEncrypted
        }
        if let legacyPlain = legacyPlainKeys["apiKey.embedding"], !legacyPlain.isEmpty {
            encryptedKeys[storageKey] = legacyPlain
            legacyPlainKeys.removeValue(forKey: "apiKey.embedding")
            return legacyPlain
        }
        return ""
    }

    private func encryptedProviderKey(for optionID: String) -> String {
        "encryptedApiKey.embedding.\(optionID)"
    }
}

private func withIsolatedAISettingsDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suiteName = "LeafReaderTests.AISettingsStore.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "could not create isolated defaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    try AISettingsStore.withDefaults(defaults) {
        try body(defaults)
    }
}

enum AISettingsLogicTests {
    static func testEmbeddingDefaults() throws {
        let legacySiliconFlow = selectedEmbeddingOption(savedEndpoint: "https://api.siliconflow.com/v1/embeddings")
        try expectEqual(legacySiliconFlow.id, "siliconflow", "legacy SiliconFlow endpoint should map to provider")
        try expectEqual(embeddingModelName(savedModel: "", savedEndpoint: "https://api.siliconflow.cn/v1/embeddings"), "Qwen/Qwen3-Embedding-8B", "SiliconFlow should default to its own model")

        let siliconFlow = selectedEmbeddingOption(savedEndpoint: "https://api.siliconflow.cn/v1/embeddings")
        let payload = embeddingPayload(option: siliconFlow, model: "Qwen/Qwen3-Embedding-8B", input: ["hello"])
        try expectEqual(payload["encoding_format"] as? String, "float", "SiliconFlow payload should request float embeddings")

        let localCustom = selectedEmbeddingOption(savedEndpoint: "http://127.0.0.1:9999/v1/embeddings")
        try expectEqual(localCustom.requiresAPIKey, false, "custom local embedding endpoints should not require API key")
    }

    static func testAISettingsStoreInjectedDefaultsModelSelection() throws {
        try withIsolatedAISettingsDefaults { defaults in
            try expectEqual(AISettingsStore.selectedModel.id, "deepseek-v4-flash", "missing selected model should use the first built-in model")

            defaults.set("openai-gpt-4-1", forKey: AISettingsStore.selectedModelKey)
            try expectEqual(AISettingsStore.selectedModel.id, "openai-gpt-4-1", "selected model should read from injected defaults")

            defaults.set(AISettingsStore.customModelID, forKey: AISettingsStore.selectedModelKey)
            defaults.set(" https://example.com/v1/chat/completions ", forKey: AISettingsStore.customEndpointKey)
            defaults.set(" custom-chat ", forKey: AISettingsStore.customModelNameKey)
            let custom = AISettingsStore.selectedModel
            try expectEqual(custom.id, AISettingsStore.customModelID, "custom model selection should use injected defaults")
            try expectEqual(custom.endpoint.absoluteString, "https://example.com/v1/chat/completions", "custom endpoint should be trimmed")
            try expectEqual(custom.model, "custom-chat", "custom model name should be trimmed")
        }
    }

    static func testAISettingsStoreInjectedDefaultsEmbeddingAndToggles() throws {
        try withIsolatedAISettingsDefaults { defaults in
            defaults.set("https://api.siliconflow.cn/v1/embeddings", forKey: AISettingsStore.embeddingEndpointKey)
            try expectEqual(AISettingsStore.selectedEmbeddingEndpointOption.id, "siliconflow", "embedding endpoint should read from injected defaults")
            try expectEqual(AISettingsStore.embeddingModelName, "Qwen/Qwen3-Embedding-8B", "embedding model should fall back to selected provider default")

            defaults.set(" custom-embedding ", forKey: AISettingsStore.embeddingModelNameKey)
            try expectEqual(AISettingsStore.embeddingModelName, "custom-embedding", "saved embedding model should be trimmed")

            try expect(AISettingsStore.speakSelectedWordEnabled, "speak selected word should default to enabled")
            AISettingsStore.saveSpeakSelectedWordEnabled(false)
            try expect(!AISettingsStore.speakSelectedWordEnabled, "speak selected word should save to injected defaults")

            try expect(!AISettingsStore.autoEmbeddingIndexEnabled, "auto embedding index should default to disabled")
            AISettingsStore.saveAutoEmbeddingIndexEnabled(true)
            try expect(AISettingsStore.autoEmbeddingIndexEnabled, "auto embedding index should save to injected defaults")

            try expect(!AISettingsStore.saveAIConversationEnabled, "AI conversation saving should default to disabled")
            AISettingsStore.saveAIConversationEnabled(true)
            try expect(AISettingsStore.saveAIConversationEnabled, "AI conversation saving should save to injected defaults")
        }
    }

    static func testAISettingsStoreSpeechSelectionValidation() throws {
        try withIsolatedAISettingsDefaults { defaults in
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "speech runtime should default to KittenTTS")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Jasper", "KittenTTS voice should default to Jasper")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "af_heart", "Kokoro voice should default to Heart")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "Piper voice should default to Lessac High")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "speech speed should default to normal")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "kitten").contains { $0.id == "Jasper" }, "KittenTTS voice options should include Jasper")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "kokoro").contains { $0.id == "af_heart" }, "Kokoro voice options should include Heart")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "piper").contains { $0.id == "en_US-lessac-high" }, "Piper voice options should include Lessac High")

            AISettingsStore.saveSelectedSpeechRuntimeID("kitten")
            AISettingsStore.saveKittenSpeechVoiceID("Bella")
            AISettingsStore.saveKokoroSpeechVoiceID("zf_001")
            AISettingsStore.savePiperSpeechVoiceID("en_US-lessac-high")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "valid speech runtime should save")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Bella", "valid KittenTTS voice should save")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "valid Kokoro voice should save")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "valid Piper voice should save")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "valid speech speed should save")

            AISettingsStore.saveSelectedSpeechRuntimeID("missing-runtime")
            AISettingsStore.saveKittenSpeechVoiceID("Dragon")
            AISettingsStore.saveKokoroSpeechVoiceID("Dragon")
            AISettingsStore.savePiperSpeechVoiceID("Dragon")
            AISettingsStore.saveSpeechSpeedID("warp")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "invalid speech runtime should be ignored")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Bella", "invalid KittenTTS voice should be ignored")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "invalid Kokoro voice should be ignored")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "invalid Piper voice should be ignored")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "invalid speech speed should be ignored")

            AISettingsStore.saveSpeechVoiceID("Luna", runtimeID: "kitten")
            AISettingsStore.saveSpeechVoiceID("zf_002", runtimeID: "kokoro")
            AISettingsStore.saveSpeechVoiceID("en_US-lessac-high", runtimeID: "piper")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "kitten"), "Luna", "generic KittenTTS voice save should use the KittenTTS list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "kokoro"), "zf_002", "generic Kokoro voice save should use the Kokoro list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "piper"), "en_US-lessac-high", "generic Piper voice save should use the Piper list")
            try expectEqual(AISettingsStore.speechVoiceTitle(for: "zf_002", runtimeID: "kokoro"), AppText.localized("中文女声 2", "Chinese Female 2"), "Kokoro preview should use the display voice title")

            defaults.set(" missing-runtime ", forKey: AISettingsStore.selectedSpeechRuntimeKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.kittenSpeechVoiceKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.kokoroSpeechVoiceKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.piperSpeechVoiceKey)
            defaults.set(" warp ", forKey: AISettingsStore.speechSpeedKey)
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "invalid stored speech runtime should fall back")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Jasper", "invalid stored KittenTTS voice should fall back")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "af_heart", "invalid stored Kokoro voice should fall back")
            try expectEqual(AISettingsStore.selectedPiperSpeechVoiceID, "en_US-lessac-high", "invalid stored Piper voice should fall back")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "invalid stored speech speed should fall back")
        }
    }

    static func testPiperSpeechSpeedLengthScale() throws {
        try withIsolatedAISettingsDefaults { _ in
            try expectEqual(AISettingsStore.piperLengthScale, 1.0, "Piper normal speed should use the default length scale")
            AISettingsStore.saveSpeechSpeedID("fast")
            try expectEqual(AISettingsStore.piperLengthScale, 0.72, "Piper fast speed should shorten phoneme length")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.piperLengthScale, 1.35, "Piper slow speed should lengthen phonemes")
            AISettingsStore.saveSpeechSpeedID("verySlow")
            try expectEqual(AISettingsStore.piperLengthScale, 1.65, "Piper very slow speed should lengthen phonemes further")
        }
    }

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

    static func testSpeechSynthesisErrorMessagesAreActionable() throws {
        try expect(
            SpeechSynthesisError.runtimeUnavailable("Piper").localizedDescription.contains("Piper"),
            "runtime errors should name the failing runtime"
        )
        try expect(
            SpeechSynthesisError.voiceUnavailable("Kokoro").localizedDescription.contains(AppText.localized("重新下载", "Download")),
            "voice errors should tell the user to download the model again"
        )
        try expect(
            SpeechSynthesisError.workerTimedOut("Kokoro").localizedDescription.contains(AppText.localized("超时", "timed out")),
            "timeout errors should be distinguishable from missing-model errors"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "Piper",
                diagnostic: "dyld: Library not loaded: @rpath/libonnxruntime.dylib"
            ),
            .dependencyMissing("Piper"),
            "dynamic-library failures should be classified as missing dependencies"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "Kokoro",
                diagnostic: "failed to load onnx model config"
            ),
            .modelLoadFailed("Kokoro"),
            "model/config failures should be classified as model load failures"
        )
        try expectEqual(
            SpeechSynthesisError.classifiedProcessFailure(
                runtime: "KittenTTS",
                diagnostic: "address already in use"
            ),
            .portUnavailable("KittenTTS"),
            "local server port failures should be classified separately"
        )
        try expect(
            SpeechSynthesisError.modelLoadFailed("Piper").supportsRedownload,
            "model load failures should support one-click redownload"
        )
        try expect(
            !SpeechSynthesisError.dependencyMissing("Piper").supportsRedownload,
            "dependency failures should point users to app/runtime repair instead of model redownload"
        )
    }

    static func testSpeechRuntimeInferenceFailureStore() throws {
        let runtime = SpeechRuntimeResourceManager.Runtime.piper
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)
        SpeechRuntimeInferenceFailureStore.record(
            .workerTimedOut("Piper"),
            for: runtime,
            voiceID: "en_US-lessac-high",
            context: "preview",
            text: "Hello",
            outputURL: URL(fileURLWithPath: "/tmp/leafreader-piper.wav")
        )
        let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime)
        try expectEqual(failure?.runtimeID, "piper", "inference failure should store the runtime id")
        try expectEqual(failure?.voiceID, "en_US-lessac-high", "inference failure should store the voice id")
        try expectEqual(failure?.context, "preview", "inference failure should store the failure context")
        try expectEqual(failure?.textLength, 5, "inference failure should store text length for diagnostics")
        try expectEqual(
            SpeechRuntimeInferenceFailureStore.relativeTimeText(since: 100, now: 220),
            AppText.localized("2分钟前", "2m ago"),
            "inference failure status should format a relative failure time"
        )
        SpeechRuntimeInferenceFailureStore.clear(for: runtime)
    }

    static func testSpeechRuntimeDownloadURLsUseReleaseAssets() throws {
        let kittenURL = SpeechRuntimeResourceManager.Runtime.kitten.downloadURL.absoluteString
        let kokoroURL = SpeechRuntimeResourceManager.Runtime.kokoro.downloadURL.absoluteString
        let piperURL = SpeechRuntimeResourceManager.Runtime.piper.downloadURL.absoluteString

        try expect(kittenURL.hasSuffix("/kitten-tts-rs-macos-arm64.tar.gz"), "KittenTTS should use the release asset archive")
        try expect(kokoroURL.hasSuffix("/kokoro-coreml-macos-arm64.tar.gz"), "Kokoro should use the release asset archive")
        try expect(piperURL.hasSuffix("/piper-tts-macos-arm64.tar.gz"), "Piper should use the release asset archive")
        try expect(kittenURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "KittenTTS should use the stable speech runtime asset release")
        try expect(kokoroURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Kokoro should use the stable speech runtime asset release")
        try expect(piperURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Piper should use the stable speech runtime asset release")
        try expect(SpeechRuntimeResourceManager.Runtime.modelManifestURL.absoluteString.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Speech model manifest should use the same stable asset release")
        try expect(SpeechRuntimeResourceManager.Runtime.modelManifestURL.absoluteString.hasSuffix("/speech-models-manifest.json"), "Speech model manifest should use the release asset manifest")
        try expect(!kittenURL.contains("/v1.4.18/"), "KittenTTS download URL should not be pinned to the old 1.4.18 release")
    }

    static func testSpeechModelManifestParsingAndChecksumValidation() throws {
        let manifestJSON = """
        {
          "generatedAt": "2026-05-23T06:08:12Z",
          "assets": [
            {
              "name": "kitten-tts-rs-macos-arm64.tar.gz",
              "size": 5,
              "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            }
          ]
        }
        """.data(using: .utf8)!
        let manifest = try SpeechRuntimeResourceManager.decodeModelManifest(manifestJSON)
        let asset = manifest.asset(named: "kitten-tts-rs-macos-arm64.tar.gz")
        try expectEqual(asset?.sha256, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "manifest lookup should return the matching asset digest")
        try expectEqual(asset?.size, 5, "manifest lookup should return the matching asset size")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-sha256-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("hello".utf8).write(to: fileURL)
        try SpeechRuntimeResourceManager.validateArchiveManifest(fileURL, asset: asset)

        do {
            try SpeechRuntimeResourceManager.validateArchiveChecksum(fileURL, expectedSHA256: String(repeating: "0", count: 64))
            throw TestFailure(description: "checksum mismatch should throw")
        } catch let error as NSError {
            try expectEqual(error.domain, SpeechRuntimeResourceManager.downloadErrorDomain, "checksum mismatch should use the download error domain")
            try expectEqual(error.code, -7, "checksum mismatch should use the checksum error code")
        }

        let wrongSize = SpeechModelManifest.Asset(name: "kitten-tts-rs-macos-arm64.tar.gz", size: 6, sha256: asset!.sha256)
        do {
            try SpeechRuntimeResourceManager.validateArchiveManifest(fileURL, asset: wrongSize)
            throw TestFailure(description: "size mismatch should throw")
        } catch let error as NSError {
            try expectEqual(error.domain, SpeechRuntimeResourceManager.downloadErrorDomain, "size mismatch should use the download error domain")
            try expectEqual(error.code, -8, "size mismatch should use the size error code")
        }
    }

    static func testSpeechRuntimeResumeContentRangeValidation() throws {
        try expectEqual(
            SpeechRuntimeResourceManager.contentRangeStart("bytes 1024-2047/4096"),
            1024,
            "resume validation should parse the Content-Range start byte"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.contentRangeStart(" bytes 0-99/100 "),
            0,
            "resume validation should tolerate Content-Range whitespace"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.contentRangeStart("bytes 1024-2047/*"),
            1024,
            "resume validation should allow unknown total sizes"
        )
        try expect(
            SpeechRuntimeResourceManager.contentRangeStart("bytes */4096") == nil,
            "unsatisfied Content-Range responses should not look resumable"
        )
        try expect(
            SpeechRuntimeResourceManager.contentRangeStart("items 1024-2047/4096") == nil,
            "non-byte Content-Range responses should be rejected"
        )
    }

    static func testSpeechRuntimePartialRestartPolicy() throws {
        let resumeExpired = NSError(domain: SpeechRuntimeResourceManager.downloadErrorDomain, code: 416)
        let resumeMismatch = NSError(domain: SpeechRuntimeResourceManager.downloadErrorDomain, code: SpeechRuntimeResourceManager.resumeRangeMismatchCode)
        let checksumMismatch = NSError(domain: SpeechRuntimeResourceManager.downloadErrorDomain, code: -7)
        let networkFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)

        try expect(
            SpeechRuntimeResourceManager.shouldRetryDownload(error: resumeMismatch, attempt: 1),
            "mismatched resume responses should retry from a clean download"
        )
        try expect(
            SpeechRuntimeResourceManager.shouldRestartWithoutPartialDownload(error: resumeExpired),
            "expired resume ranges should discard the partial archive"
        )
        try expect(
            SpeechRuntimeResourceManager.shouldRestartWithoutPartialDownload(error: resumeMismatch),
            "mismatched resume ranges should discard the partial archive"
        )
        try expect(
            SpeechRuntimeResourceManager.shouldRestartWithoutPartialDownload(error: checksumMismatch),
            "checksum failures should discard the corrupt partial archive"
        )
        try expect(
            !SpeechRuntimeResourceManager.shouldRestartWithoutPartialDownload(error: networkFailure),
            "transient network failures should keep the partial archive for resume"
        )
    }

    static func testSpeechRuntimePartialMetadataValidationAndIfRange() throws {
        let asset = SpeechModelManifest.Asset(
            name: "piper-tts-macos-arm64.tar.gz",
            size: 105541145,
            sha256: "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5"
        )
        let metadata = SpeechRuntimeResourceManager.PartialDownloadMetadata(
            downloadURL: SpeechRuntimeResourceManager.Runtime.piper.downloadURL.absoluteString,
            assetName: asset.name,
            expectedSize: asset.size,
            sha256: asset.sha256,
            eTag: " \"abc\" ",
            lastModified: "Wed, 24 May 2026 00:00:00 GMT"
        )
        try expect(
            SpeechRuntimeResourceManager.partialDownloadMetadataMatches(
                metadata,
                runtime: .piper,
                asset: asset
            ),
            "partial metadata should match the same URL and manifest asset"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.ifRangeHeaderValue(for: metadata),
            "\"abc\"",
            "If-Range should prefer a trimmed ETag"
        )

        let changedAsset = SpeechModelManifest.Asset(
            name: asset.name,
            size: asset.size,
            sha256: String(repeating: "0", count: 64)
        )
        try expect(
            !SpeechRuntimeResourceManager.partialDownloadMetadataMatches(
                metadata,
                runtime: .piper,
                asset: changedAsset
            ),
            "partial metadata should reject changed asset checksums"
        )

        let lastModifiedOnly = SpeechRuntimeResourceManager.PartialDownloadMetadata(
            downloadURL: metadata.downloadURL,
            assetName: metadata.assetName,
            expectedSize: metadata.expectedSize,
            sha256: metadata.sha256,
            eTag: " ",
            lastModified: "Wed, 24 May 2026 00:00:00 GMT"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.ifRangeHeaderValue(for: lastModifiedOnly),
            "Wed, 24 May 2026 00:00:00 GMT",
            "If-Range should fall back to Last-Modified when ETag is missing"
        )
    }

    static func testSpeechRuntimeDownloadConfigurationAndProgressTotals() throws {
        let configuration = SpeechRuntimeResourceManager.downloadSessionConfiguration()
        try expectEqual(
            configuration.timeoutIntervalForRequest,
            30,
            "speech model downloads should have a bounded per-request timeout"
        )
        try expectEqual(
            configuration.timeoutIntervalForResource,
            60 * 60,
            "speech model downloads should allow large archives enough total download time"
        )
        try expect(
            configuration.waitsForConnectivity,
            "speech model downloads should wait for connectivity on transient offline states"
        )

        let asset = SpeechModelManifest.Asset(
            name: "piper-tts-macos-arm64.tar.gz",
            size: 105541145,
            sha256: "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.expectedDownloadTotalBytes(asset: asset),
            105541145,
            "progress should use manifest size when available"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.expectedDownloadTotalBytes(asset: nil),
            nil,
            "progress should fall back to response length without manifest size"
        )
    }

    static func testSpeechModelManifestDecodeFallsBackToBundledManifest() throws {
        let bundled = SpeechModelManifest(
            generatedAt: "2026-05-25T00:00:00Z",
            assets: [
                SpeechModelManifest.Asset(
                    name: "kitten-tts-rs-macos-arm64.tar.gz",
                    size: 77638385,
                    sha256: "90d917517468f93e5c31b17184d777cba9fee51fd90197deeaa5bd2f406d0e81"
                )
            ]
        )
        let fallbackResult = SpeechRuntimeResourceManager.modelManifestDecodeResult(
            data: Data("not json".utf8),
            bundledManifest: bundled
        )
        switch fallbackResult {
        case .success(let manifest):
            try expectEqual(
                manifest?.asset(named: "kitten-tts-rs-macos-arm64.tar.gz")?.size,
                77638385,
                "invalid remote manifest should fall back to the bundled manifest"
            )
        case .failure(let error):
            throw TestFailure(description: "invalid remote manifest should not fail when bundled manifest exists: \(error)")
        }

        let failureResult = SpeechRuntimeResourceManager.modelManifestDecodeResult(
            data: Data("not json".utf8),
            bundledManifest: nil
        )
        if case .success = failureResult {
            throw TestFailure(description: "invalid remote manifest should fail when no bundled manifest exists")
        }
    }

    static func testSpeechRuntimeInstallDiskSpacePolicy() throws {
        let required = SpeechRuntimeResourceManager.requiredInstallFreeSpaceBytes(archiveSize: 100)
        try expectEqual(
            required,
            200 * 1024 * 1024 + 300,
            "install disk-space policy should reserve room for archive, extraction, and a safety margin"
        )
        try expect(
            SpeechRuntimeResourceManager.hasEnoughFreeSpace(availableBytes: required, requiredBytes: required),
            "exactly enough free space should be accepted"
        )
        try expect(
            !SpeechRuntimeResourceManager.hasEnoughFreeSpace(availableBytes: required - 1, requiredBytes: required),
            "insufficient free space should be rejected before install"
        )
        try expect(
            SpeechRuntimeResourceManager.hasEnoughFreeSpace(availableBytes: nil, requiredBytes: required),
            "unknown free space should not block installation"
        )
    }

    static func testBundledSpeechModelManifestParses() throws {
        let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mac-app/Resources/speech-models-manifest.json")
        let manifest = try SpeechRuntimeResourceManager.decodeModelManifest(Data(contentsOf: manifestURL))
        try expectEqual(
            manifest.asset(named: "kitten-tts-rs-macos-arm64.tar.gz")?.sha256,
            "90d917517468f93e5c31b17184d777cba9fee51fd90197deeaa5bd2f406d0e81",
            "bundled manifest should include the KittenTTS model archive"
        )
        try expectEqual(
            manifest.asset(named: "kokoro-coreml-macos-arm64.tar.gz")?.size,
            694363430,
            "bundled manifest should include Kokoro model size"
        )
        try expectEqual(
            manifest.asset(named: "piper-tts-macos-arm64.tar.gz")?.sha256,
            "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5",
            "bundled manifest should include Piper model checksum"
        )
    }

    static func testSpeechRuntimeAvailabilityText() throws {
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: true, downloaded: true, minimumSystemVersionText: "macOS 14.0"),
            nil,
            "available runtimes should not show an unavailable reason"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: false, downloaded: true, minimumSystemVersionText: "macOS 14.0"),
            AppText.localized("需要 macOS 14.0", "Requires macOS 14.0"),
            "unsupported downloaded runtimes should show the macOS requirement"
        )
        try expectEqual(
            SpeechRuntimeResourceManager.availabilityText(isSupported: true, downloaded: false, minimumSystemVersionText: "macOS 12.0"),
            AppText.localized("未下载", "Not downloaded"),
            "missing runtimes should show that the model is not downloaded"
        )
    }

    static func testPiperRuntimeRequiresPhonemizeResources() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let executable = root.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try expect(
            !SpeechRuntimeResourceManager.piperRuntimePathsExist(in: root),
            "Piper runtime should not be runnable without phonemize libraries and espeak data"
        )

        try fileManager.createDirectory(
            at: root.appendingPathComponent("piper-phonemize/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expect(
            !SpeechRuntimeResourceManager.piperRuntimePathsExist(in: root),
            "Piper runtime should not be runnable without espeak data"
        )

        try fileManager.createDirectory(
            at: root.appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expect(
            SpeechRuntimeResourceManager.piperRuntimePathsExist(in: root),
            "Piper runtime should be runnable when executable, phonemize libraries, and espeak data are present"
        )
    }

    static func testPiperAnyVoiceAcceptsNonDefaultVoice() throws {
        let fileManager = FileManager.default
        let voiceDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-voices-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: voiceDirectory) }

        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx.json"))

        try expect(
            SpeechRuntimeResourceManager.piperAnyVoicePathsExist(in: voiceDirectory),
            "Piper should be available when any complete voice model and config pair exists"
        )
        try expect(
            !SpeechRuntimeResourceManager.piperVoicePathsExist(in: voiceDirectory),
            "default Piper voice checks should remain voice-specific"
        )
    }

    static func testPiperModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("piper-tts-runtime", isDirectory: true)
        let voiceDirectory = root.appendingPathComponent("piper-voices", isDirectory: true)
        let executable = runtimeDirectory.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: runtimeDirectory.appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeResourceManager.piperRuntimeAndVoicePathsExist(
                installDirectories: [runtimeDirectory],
                voiceDirectory: voiceDirectory
            ),
            "Piper should remain unavailable after runtime install until a voice model is downloaded"
        )

        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-lessac-high.onnx.json"))
        try expect(
            SpeechRuntimeResourceManager.piperRuntimeAndVoicePathsExist(
                installDirectories: [runtimeDirectory],
                voiceDirectory: voiceDirectory
            ),
            "Piper should become available once the downloaded voice model and config are in the voice cache"
        )
    }

    static func testKokoroModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let runtimeDirectory = root.appendingPathComponent("kokoro-coreml", isDirectory: true)
        let modelCacheRoot = root.appendingPathComponent("Models", isDirectory: true)
        let executable = runtimeDirectory.appendingPathComponent("fluidaudiocli")
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeResourceManager.kokoroRuntimeAndModelPathsExist(
                installDirectories: [runtimeDirectory],
                modelCacheRoot: modelCacheRoot
            ),
            "Kokoro should remain unavailable after runtime install until model cache files are downloaded"
        )

        let aneDirectory = modelCacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
        let g2pDirectory = modelCacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        try fileManager.createDirectory(at: aneDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: g2pDirectory, withIntermediateDirectories: true)
        for fileName in [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json"
        ] {
            try Data().write(to: aneDirectory.appendingPathComponent(fileName))
        }
        for fileName in ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json"] {
            try Data().write(to: g2pDirectory.appendingPathComponent(fileName))
        }

        try expect(
            SpeechRuntimeResourceManager.kokoroRuntimeAndModelPathsExist(
                installDirectories: [runtimeDirectory],
                modelCacheRoot: modelCacheRoot
            ),
            "Kokoro should become available once the downloaded model cache contains all required files"
        )
    }

    static func testKittenModelDownloadMakesBundledRuntimeAvailable() throws {
        let fileManager = FileManager.default
        let runtimeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kitten-availability-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: runtimeDirectory) }

        let executable = runtimeDirectory.appendingPathComponent("kitten-tts-aarch64-macos/kitten-tts-server")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try expect(
            !SpeechRuntimeResourceManager.kittenRuntimeAndModelPathsExist(installDirectories: [runtimeDirectory]),
            "KittenTTS should remain unavailable after runtime install until model files are downloaded"
        )

        let modelDirectory = runtimeDirectory.appendingPathComponent("kitten-tts-mini", isDirectory: true)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data().write(to: modelDirectory.appendingPathComponent("kitten_tts_mini_v0_8.onnx"))
        try Data().write(to: modelDirectory.appendingPathComponent("voices.npz"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))

        try expect(
            SpeechRuntimeResourceManager.kittenRuntimeAndModelPathsExist(installDirectories: [runtimeDirectory]),
            "KittenTTS should become available once the downloaded model directory contains all required files"
        )
    }

    static func testPiperArchiveValidationRequiresPackagedVoice() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-piper-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let executable = root.appendingPathComponent("piper/piper")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        do {
            try SpeechRuntimeResourceManager.validateExtractedRuntime(.piper, in: root)
            throw TestFailure(description: "Piper archive validation should reject archives without a packaged voice")
        } catch let error as NSError {
            try expectEqual(error.domain, "LeafReader.SpeechRuntime", "Piper archive validation should use the speech runtime domain")
            try expectEqual(error.code, -4, "Piper archive validation should report missing required files")
        }

        let voiceDirectory = root.appendingPathComponent("Voices", isDirectory: true)
        try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try Data().write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx"))
        try Data("{}".utf8).write(to: voiceDirectory.appendingPathComponent("en_US-ryan-medium.onnx.json"))

        try SpeechRuntimeResourceManager.validateExtractedRuntime(.piper, in: root)
    }

    static func testSpeechRuntimeInstallManifestFiltersExternalCachePaths() throws {
        let cacheRoot = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
        let validCacheDirectory = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let piperCacheRoot = SpeechRuntimeResourceManager.Runtime.piperVoiceCacheRoot
        let validPiperCacheDirectory = piperCacheRoot.appendingPathComponent("en", isDirectory: true)
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-external-cache-\(UUID().uuidString)", isDirectory: true)
        let manifest = SpeechRuntimeResourceManager.InstallManifest(
            runtimeID: SpeechRuntimeResourceManager.Runtime.kokoro.id,
            cacheDirectoryPaths: [
                validCacheDirectory.path,
                cacheRoot.path,
                validPiperCacheDirectory.path,
                piperCacheRoot.path,
                externalDirectory.path
            ]
        )

        try expectEqual(
            manifest.cacheDirectories,
            [validCacheDirectory, validPiperCacheDirectory],
            "install manifests should only expose child directories inside known speech model caches"
        )
    }

    static func testKokoroCacheInstallTransactionRollbackAndCommit() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("leafreader-kokoro-cache-transaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let existing = root.appendingPathComponent("existing", isDirectory: true)
        let existingMarker = existing.appendingPathComponent("marker.txt")
        let replacement = root.appendingPathComponent("replacement", isDirectory: true)
        let replacementMarker = replacement.appendingPathComponent("marker.txt")
        let backup = root.appendingPathComponent("backup", isDirectory: true)
        try fileManager.createDirectory(at: existing, withIntermediateDirectories: true)
        try "old".write(to: existingMarker, atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: replacement, withIntermediateDirectories: true)
        try "new".write(to: replacementMarker, atomically: true, encoding: .utf8)

        var rollbackTransaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        try rollbackTransaction.replace(source: replacement, destination: existing, backup: backup)
        rollbackTransaction.rollback()
        try expectEqual(
            try String(contentsOf: existingMarker, encoding: .utf8),
            "old",
            "rollback should restore the previous cache directory"
        )
        try expect(!fileManager.fileExists(atPath: backup.path), "rollback should remove the cache backup")

        let committedReplacement = root.appendingPathComponent("committed-replacement", isDirectory: true)
        let committedMarker = committedReplacement.appendingPathComponent("marker.txt")
        let committedBackup = root.appendingPathComponent("committed-backup", isDirectory: true)
        try fileManager.createDirectory(at: committedReplacement, withIntermediateDirectories: true)
        try "committed".write(to: committedMarker, atomically: true, encoding: .utf8)

        var commitTransaction = KokoroCacheInstallTransaction(fileManager: fileManager)
        try commitTransaction.replace(source: committedReplacement, destination: existing, backup: committedBackup)
        commitTransaction.commit()
        try expectEqual(
            try String(contentsOf: existingMarker, encoding: .utf8),
            "committed",
            "commit should keep the replacement cache directory"
        )
        try expect(!fileManager.fileExists(atPath: committedBackup.path), "commit should remove the cache backup")
        try expectEqual(
            commitTransaction.installedDirectories,
            [existing],
            "commit should keep installed directory records for manifest writing"
        )
    }

    static func testNetworkErrorFormattingSanitizesSensitiveBody() throws {
        let body = #"{"error":"bad key","api_key":"sk-test","Authorization":"Bearer abc.def","token":"secret"}"#
        let message = NetworkErrorFormatter.httpErrorDescription(prefix: "Model", statusCode: 401, body: body)

        try expect(message.hasPrefix("Model HTTP 401:"), "HTTP error should include prefix and status")
        try expect(!message.contains("sk-test"), "API keys should be redacted")
        try expect(!message.contains("abc.def"), "Bearer tokens should be redacted")
        try expect(!message.contains(#""token":"secret""#), "token fields should be redacted")
        try expect(message.contains("[redacted]"), "redacted marker should be visible")
    }

    static func testNetworkErrorFormattingTruncatesLongBody() throws {
        let longBody = String(repeating: "x", count: 5000)
        let sanitized = NetworkErrorFormatter.sanitizedBody(longBody)

        try expectEqual(sanitized.count, 4099, "long HTTP bodies should be truncated with ellipsis")
        try expect(sanitized.hasSuffix("..."), "truncated HTTP bodies should end with ellipsis")
    }

    static func testAIResponseParserParsesNonStreamingResponses() throws {
        let responsesJSON: [String: Any] = [
            "output": [
                [
                    "content": [
                        ["type": "output_text", "text": "Responses answer"]
                    ]
                ]
            ]
        ]
        try expectEqual(
            AIResponseParser.responseText(from: responsesJSON, provider: "openai"),
            "Responses answer",
            "Responses API output content should parse"
        )

        let chatJSON: [String: Any] = [
            "choices": [
                ["message": ["content": "Chat answer"]]
            ]
        ]
        try expectEqual(
            AIResponseParser.responseText(from: chatJSON, provider: "openai"),
            "Chat answer",
            "Chat completions message content should parse"
        )

        let claudeJSON: [String: Any] = [
            "content": [
                ["type": "text", "text": "Claude "],
                ["type": "text", "text": "answer"]
            ]
        ]
        try expectEqual(
            AIResponseParser.responseText(from: claudeJSON, provider: "claude"),
            "Claude answer",
            "Claude text blocks should join"
        )
    }

    static func testAIResponseParserParsesStreamingDeltas() throws {
        try expectEqual(
            AIResponseParser.deltaText(
                fromStreamLine: #"data: {"type":"response.output_text.delta","delta":"Hi"}"#,
                provider: "openai"
            ),
            "Hi",
            "Responses stream delta should parse"
        )
        try expectEqual(
            AIResponseParser.deltaText(
                fromStreamLine: #"data: {"choices":[{"delta":{"content":" there"}}]}"#,
                provider: "openai"
            ),
            " there",
            "chat completion stream delta should parse"
        )
        try expectEqual(
            AIResponseParser.deltaText(
                fromStreamLine: #"{"delta":{"text":"Claude delta"}}"#,
                provider: "claude"
            ),
            "Claude delta",
            "Claude stream delta should parse"
        )
        try expectEqual(
            AIResponseParser.deltaText(
                fromStreamLine: #"data: {"choices":[{"delta":{"reasoning_content":"hidden"}}]}"#,
                provider: "openai"
            ),
            nil,
            "reasoning-only deltas should be ignored"
        )
        try expectEqual(
            AIResponseParser.deltaText(fromStreamLine: "data: [DONE]", provider: "openai"),
            nil,
            "done sentinel should not emit visible text"
        )
    }

    static func testEmbeddingKeyIsolation() throws {
        var store = EmbeddingKeyStore()
        store.saveEmbeddingKey("openai-key", optionID: "openai")
        try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "saved key should be returned for its provider")
        try expectEqual(store.embeddingKey(for: "siliconflow"), "", "unsaved provider should not inherit another provider key")

        store.saveEmbeddingKey("silicon-key", optionID: "siliconflow")
        try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "saving another provider should not overwrite OpenAI key")
        try expectEqual(store.embeddingKey(for: "siliconflow"), "silicon-key", "provider should keep its own key")

        store.saveEmbeddingKey("", optionID: "siliconflow")
        try expectEqual(store.embeddingKey(for: "siliconflow"), "", "clearing one provider should not reveal fallback key")
        try expectEqual(store.embeddingKey(for: "openai"), "openai-key", "clearing one provider should not clear another provider")
    }

    static func testEmbeddingLegacyKeyMigration() throws {
        var store = EmbeddingKeyStore(encryptedKeys: ["encryptedApiKey.embedding": "legacy-encrypted"], legacyPlainKeys: [:])
        try expectEqual(store.embeddingKey(for: "openai"), "", "non-migrating lookup should not expose legacy key")
        try expectEqual(store.embeddingKeyMigratingLegacyIfNeeded(for: "openai"), "legacy-encrypted", "legacy encrypted key should migrate to selected provider")
        try expectEqual(store.embeddingKey(for: "openai"), "legacy-encrypted", "selected provider should receive migrated key")
        try expectEqual(store.embeddingKey(for: "siliconflow"), "", "other providers should not receive migrated legacy key")
        try expectEqual(store.encryptedKeys["encryptedApiKey.embedding"] ?? "", "", "legacy encrypted key should be removed after migration")

        var plainStore = EmbeddingKeyStore(encryptedKeys: [:], legacyPlainKeys: ["apiKey.embedding": "legacy-plain"])
        try expectEqual(plainStore.embeddingKeyMigratingLegacyIfNeeded(for: "siliconflow"), "legacy-plain", "legacy plain key should migrate to selected provider")
        try expectEqual(plainStore.embeddingKey(for: "siliconflow"), "legacy-plain", "selected provider should receive migrated plain key")
        try expectEqual(plainStore.embeddingKey(for: "openai"), "", "plain legacy migration should not leak to other providers")
        try expectEqual(plainStore.legacyPlainKeys["apiKey.embedding"] ?? "", "", "legacy plain key should be removed after migration")
    }
}
