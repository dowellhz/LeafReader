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

private extension URL {
    var isLocalEndpoint: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
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
