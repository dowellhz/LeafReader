import Foundation

enum AISettingsLogicTests {
    static func testSecureCredentialStoreRoundTripAndLegacyMigration() throws {
        let suiteName = "LeafReaderTests.LocalSecretStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create secret store defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = InMemoryLocalSecretStore()
        let account = "encryptedApiKey.openai"
        defaults.set(try legacyEncryptedCredential(" legacy-key "), forKey: account)

        try LocalEncryptedStore.withStore(store, legacyDefaults: defaults) {
            try expectEqual(LocalEncryptedStore.string(forKey: account), "legacy-key", "legacy encrypted key should migrate")
            try expectEqual(store.values[account], "legacy-key", "migrated key should be verified in secure storage")
            try expect(defaults.object(forKey: account) == nil, "verified legacy encrypted data should be deleted")

            try expect(LocalEncryptedStore.save(" replacement ", forKey: account), "secure key save should succeed")
            try expectEqual(LocalEncryptedStore.string(forKey: account), "replacement", "secure key should round trip")
            try expect(LocalEncryptedStore.save("", forKey: account), "secure key delete should succeed")
            try expectEqual(LocalEncryptedStore.string(forKey: account), "", "deleted secure key should not be returned")
        }
    }

    static func testCredentialMigrationPreservesLegacyDataOnWriteFailure() throws {
        let suiteName = "LeafReaderTests.LocalSecretFailure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create secret failure defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = InMemoryLocalSecretStore()
        store.failsWrites = true
        let account = "encryptedApiKey.openai"
        let encoded = try legacyEncryptedCredential("legacy-key")
        defaults.set(encoded, forKey: account)

        try LocalEncryptedStore.withStore(store, legacyDefaults: defaults) {
            try expectEqual(LocalEncryptedStore.string(forKey: account), "legacy-key", "failed migration should still return legacy value")
            try expectEqual(defaults.string(forKey: account), encoded, "failed migration must retain legacy encrypted data")

            defaults.removeObject(forKey: account)
            let plainKey = AISettingsStore.apiKeyDefaultsKey(for: "claude")
            defaults.set("plain-key", forKey: plainKey)
            try AISettingsStore.withDefaults(defaults) {
                let model = AISettingsStore.models.first { $0.provider == "claude" }!
                try expectEqual(AISettingsStore.apiKey(for: model), "plain-key", "failed plaintext migration should remain usable")
                try expectEqual(defaults.string(forKey: plainKey), "plain-key", "failed plaintext migration must retain source data")
            }
        }
    }

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

            defaults.set(AISettingsStore.ollamaModelID, forKey: AISettingsStore.selectedModelKey)
            let ollama = AISettingsStore.selectedModel
            try expectEqual(ollama.id, AISettingsStore.ollamaModelID, "Ollama model selection should use injected defaults")
            try expectEqual(ollama.endpoint.absoluteString, "http://127.0.0.1:11434/v1/chat/completions", "Ollama should use the local OpenAI-compatible endpoint")
            try expectEqual(ollama.model, "llama3.1", "Ollama should use the default local model name")
            try expect(!ollama.requiresAPIKey, "Ollama should not require an API key")
            try expect(AISettingsStore.hasAPIKeyForSelectedModel, "Ollama should be usable without an API key")

            AISettingsStore.save(modelID: AISettingsStore.ollamaModelID, apiKey: "", customModelName: " qwen2.5:7b ")
            try expectEqual(AISettingsStore.selectedModel.model, "qwen2.5:7b", "Ollama model name should be editable and trimmed")
            try expectEqual(AISettingsStore.customModelName, "custom-chat", "Ollama model saving should not overwrite Other model name")
            try expectEqual(AISettingsStore.ollamaValidationError(modelName: "   "), "请输入 Ollama 模型 ID。", "blank Ollama model names should be rejected")

            let customIndex = AISettingsStore.models.firstIndex { $0.id == AISettingsStore.customModelID }
            let ollamaIndex = AISettingsStore.models.firstIndex { $0.id == AISettingsStore.ollamaModelID }
            let localOpenAIIndex = AISettingsStore.models.firstIndex { $0.id == AISettingsStore.localOpenAIModelID }
            try expectEqual(localOpenAIIndex, ollamaIndex.map { $0 + 1 }, "local OpenAI-compatible should appear immediately after Ollama")
            try expectEqual(customIndex, localOpenAIIndex.map { $0 + 1 }, "Other should appear immediately after local OpenAI-compatible")

            defaults.set(AISettingsStore.localOpenAIModelID, forKey: AISettingsStore.selectedModelKey)
            let localOpenAI = AISettingsStore.selectedModel
            try expectEqual(localOpenAI.id, AISettingsStore.localOpenAIModelID, "local OpenAI-compatible model selection should use injected defaults")
            try expectEqual(localOpenAI.endpoint.absoluteString, "http://127.0.0.1:8000/v1/chat/completions", "local OpenAI-compatible endpoint should default to the local chat completions endpoint")
            try expectEqual(localOpenAI.model, "gemma-4-e4b-it-4bit", "local OpenAI-compatible model should default to the oMLX test model")
            try expect(!localOpenAI.requiresAPIKey, "local OpenAI-compatible models should allow optional API keys")
            try expect(localOpenAI.acceptsAPIKey, "local OpenAI-compatible models should allow entering an optional API key")
            try expect(AISettingsStore.hasAPIKeyForSelectedModel, "local OpenAI-compatible models should be usable without a saved API key")

            AISettingsStore.save(modelID: AISettingsStore.localOpenAIModelID, apiKey: " local-key ", customEndpoint: " http://127.0.0.1:8000/v1 ", customModelName: " local-model ")
            try expectEqual(AISettingsStore.selectedModel.endpoint.absoluteString, "http://127.0.0.1:8000/v1/chat/completions", "local OpenAI-compatible /v1 endpoint should be expanded to chat completions")
            try expectEqual(AISettingsStore.selectedModel.model, "local-model", "local OpenAI-compatible model name should be editable and trimmed")
            try expectEqual(AISettingsStore.apiKey(for: AISettingsStore.selectedModel), "local-key", "local OpenAI-compatible API key should be stored separately")
            try expectEqual(AISettingsStore.localOpenAIValidationError(endpoint: "   ", modelName: "local-model"), "请输入本地 OpenAI 兼容 URL。", "blank local OpenAI-compatible endpoints should be rejected")
            try expectEqual(AISettingsStore.localOpenAIValidationError(endpoint: "http://127.0.0.1:8000/v1", modelName: "   "), "请输入模型 ID。", "blank local OpenAI-compatible model names should be rejected")
        }
    }

    static func testAIProviderDescriptors() throws {
        let claude = AISettingsStore.models.first { $0.id == "claude-3-5-sonnet" }
        let openAI = AISettingsStore.models.first { $0.id == "openai-gpt-4-1" }
        let ollama = AISettingsStore.models.first { $0.id == AISettingsStore.ollamaModelID }
        let localOpenAI = AISettingsStore.models.first { $0.id == AISettingsStore.localOpenAIModelID }
        let unknown = AIProviderDescriptor.descriptor(for: "local-minicpm")

        try expectEqual(
            claude?.providerDescriptor.chatRequestFormat,
            .anthropicMessages,
            "Claude models should carry the Anthropic request format through the provider descriptor"
        )
        try expectEqual(
            openAI?.providerDescriptor.chatRequestFormat,
            .openAICompatible,
            "OpenAI models should carry the OpenAI-compatible request format through the provider descriptor"
        )
        try expectEqual(
            ollama?.providerDescriptor.chatRequestFormat,
            .openAICompatible,
            "Ollama should use the OpenAI-compatible request format"
        )
        if let ollama {
            var request = URLRequest(url: ollama.endpoint)
            AIChatRequestBuilder.configureHeaders(for: ollama, apiKey: "", request: &request)
            try expectEqual(request.value(forHTTPHeaderField: "Authorization"), nil, "Ollama requests should not send an empty Authorization header")
        } else {
            throw TestFailure(description: "Ollama model should be available")
        }
        if let localOpenAI {
            var request = URLRequest(url: localOpenAI.endpoint)
            AIChatRequestBuilder.configureHeaders(for: localOpenAI, apiKey: "local-key", request: &request)
            try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-key", "local OpenAI-compatible requests should send Authorization when an optional API key is configured")
        } else {
            throw TestFailure(description: "local OpenAI-compatible model should be available")
        }
        try expectEqual(
            unknown.chatRequestFormat,
            .openAICompatible,
            "unknown providers should default to the OpenAI-compatible request format"
        )
        try expect(
            AISettingsStore.selectedEmbeddingProviderDescriptor.capabilities.contains(.embedding),
            "embedding endpoint options should expose a provider descriptor with embedding capability"
        )
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

    static func testAIRequestErrorTextClassifiesCommonFailures() throws {
        let missingKey = NSError(domain: "openai", code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for OpenAI"
        ])
        try expect(
            AIRequestErrorText.message(for: missingKey).contains("API Key"),
            "missing API key errors should point to model settings"
        )

        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        try expect(
            AIRequestErrorText.message(for: timeout).contains("超时"),
            "timeout errors should use a timeout-specific message"
        )

        let rateLimit = NSError(domain: "openai", code: 429, userInfo: [
            NSLocalizedDescriptionKey: "OpenAI HTTP 429: rate_limit_exceeded"
        ])
        try expect(
            AIRequestErrorText.message(for: rateLimit).contains("请求太频繁"),
            "rate limits should avoid the generic AI failure message"
        )

        let localUnexpected = NSError(domain: "local-openai", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "Unexpected response: {}"
        ])
        try expect(
            AIRequestErrorText.message(for: localUnexpected).contains("本地服务"),
            "local model response failures should explain the local service compatibility issue"
        )
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

    static func testDifficultSentencePromptContainsRequiredSections() throws {
        let prompt = AIPromptStore.difficultSentencePrompt(for: "This is the sentence.")
        try expect(prompt.contains("This is the sentence."), "difficult sentence prompt should include selected text")
        try expect(
            prompt.contains("句子结构拆解") || prompt.contains("Sentence structure"),
            "difficult sentence prompt should ask for sentence structure"
        )
        try expect(
            prompt.contains("主谓宾") || prompt.contains("Subject, verb, object"),
            "difficult sentence prompt should ask for subject, verb, object, clauses, and modifiers"
        )
        try expect(
            prompt.contains("逐层翻译") || prompt.contains("Layered translation"),
            "difficult sentence prompt should ask for layered translation"
        )
        try expect(
            prompt.contains("常见表达") || prompt.contains("Common expressions"),
            "difficult sentence prompt should ask for common expressions"
        )
        try expect(
            prompt.contains("为什么这么写") || prompt.contains("Why it is written this way"),
            "difficult sentence prompt should ask why the sentence is written that way"
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
