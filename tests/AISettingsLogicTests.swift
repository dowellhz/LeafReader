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
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "speech speed should default to normal")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "kitten").contains { $0.id == "Jasper" }, "KittenTTS voice options should include Jasper")
            try expect(AISettingsStore.speechVoiceOptions(runtimeID: "kokoro").contains { $0.id == "af_heart" }, "Kokoro voice options should include Heart")

            AISettingsStore.saveSelectedSpeechRuntimeID("kitten")
            AISettingsStore.saveKittenSpeechVoiceID("Bella")
            AISettingsStore.saveKokoroSpeechVoiceID("zf_001")
            AISettingsStore.saveSpeechSpeedID("slow")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "valid speech runtime should save")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Bella", "valid KittenTTS voice should save")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "valid Kokoro voice should save")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "valid speech speed should save")

            AISettingsStore.saveSelectedSpeechRuntimeID("missing-runtime")
            AISettingsStore.saveKittenSpeechVoiceID("Dragon")
            AISettingsStore.saveKokoroSpeechVoiceID("Dragon")
            AISettingsStore.saveSpeechSpeedID("warp")
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "invalid speech runtime should be ignored")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Bella", "invalid KittenTTS voice should be ignored")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "zf_001", "invalid Kokoro voice should be ignored")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "slow", "invalid speech speed should be ignored")

            AISettingsStore.saveSpeechVoiceID("Luna", runtimeID: "kitten")
            AISettingsStore.saveSpeechVoiceID("zf_002", runtimeID: "kokoro")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "kitten"), "Luna", "generic KittenTTS voice save should use the KittenTTS list")
            try expectEqual(AISettingsStore.selectedSpeechVoiceID(runtimeID: "kokoro"), "zf_002", "generic Kokoro voice save should use the Kokoro list")
            try expectEqual(AISettingsStore.speechVoiceTitle(for: "zf_002", runtimeID: "kokoro"), AppText.localized("中文女声 2", "Chinese Female 2"), "Kokoro preview should use the display voice title")

            defaults.set(" missing-runtime ", forKey: AISettingsStore.selectedSpeechRuntimeKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.kittenSpeechVoiceKey)
            defaults.set(" Dragon ", forKey: AISettingsStore.kokoroSpeechVoiceKey)
            defaults.set(" warp ", forKey: AISettingsStore.speechSpeedKey)
            try expectEqual(AISettingsStore.selectedSpeechRuntimeID, "kitten", "invalid stored speech runtime should fall back")
            try expectEqual(AISettingsStore.selectedKittenSpeechVoiceID, "Jasper", "invalid stored KittenTTS voice should fall back")
            try expectEqual(AISettingsStore.selectedKokoroSpeechVoiceID, "af_heart", "invalid stored Kokoro voice should fall back")
            try expectEqual(AISettingsStore.selectedSpeechSpeedID, "normal", "invalid stored speech speed should fall back")
        }
    }

    static func testSpeechRuntimeDownloadURLsUseReleaseAssets() throws {
        let kittenURL = SpeechRuntimeResourceManager.Runtime.kitten.downloadURL.absoluteString
        let kokoroURL = SpeechRuntimeResourceManager.Runtime.kokoro.downloadURL.absoluteString

        try expect(kittenURL.hasSuffix("/kitten-tts-rs-macos-arm64.tar.gz"), "KittenTTS should use the release asset archive")
        try expect(kokoroURL.hasSuffix("/kokoro-coreml-macos-arm64.tar.gz"), "Kokoro should use the release asset archive")
        try expect(kittenURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "KittenTTS should use the stable speech runtime asset release")
        try expect(kokoroURL.contains("/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/"), "Kokoro should use the stable speech runtime asset release")
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

    static func testSpeechRuntimeInstallManifestFiltersExternalCachePaths() throws {
        let cacheRoot = SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot
        let validCacheDirectory = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-external-cache-\(UUID().uuidString)", isDirectory: true)
        let manifest = SpeechRuntimeResourceManager.InstallManifest(
            runtimeID: SpeechRuntimeResourceManager.Runtime.kokoro.id,
            cacheDirectoryPaths: [
                validCacheDirectory.path,
                cacheRoot.path,
                externalDirectory.path
            ]
        )

        try expectEqual(
            manifest.cacheDirectories,
            [validCacheDirectory],
            "install manifests should only expose child directories inside the FluidAudio model cache"
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
