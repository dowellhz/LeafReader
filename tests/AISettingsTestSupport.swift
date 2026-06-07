import Foundation

struct EmbeddingEndpointOption {
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

let embeddingOptions = [
    EmbeddingEndpointOption(id: "openai", endpoint: "https://api.openai.com/v1/embeddings", defaultModel: "text-embedding-3-small"),
    EmbeddingEndpointOption(id: "siliconflow", endpoint: "https://api.siliconflow.cn/v1/embeddings", defaultModel: "Qwen/Qwen3-Embedding-8B", payloadExtras: ["encoding_format": "float"]),
    EmbeddingEndpointOption(id: "ollama", endpoint: "http://127.0.0.1:11434/api/embed", defaultModel: "nomic-embed-text", requiresAPIKey: false),
    EmbeddingEndpointOption(id: "other", endpoint: "", defaultModel: "")
]

func selectedEmbeddingOption(savedEndpoint: String) -> EmbeddingEndpointOption {
    if let option = embeddingOptions.first(where: { $0.endpoint == savedEndpoint }) {
        return option
    }
    if savedEndpoint == "https://api.siliconflow.com/v1/embeddings" {
        return embeddingOptions.first { $0.id == "siliconflow" }!
    }
    let requiresKey = !(URL(string: savedEndpoint)?.isLocalEndpoint ?? false)
    return EmbeddingEndpointOption(id: "other", endpoint: savedEndpoint, defaultModel: "", requiresAPIKey: requiresKey)
}

func embeddingModelName(savedModel: String, savedEndpoint: String) -> String {
    if !savedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return savedModel
    }
    let defaultModel = selectedEmbeddingOption(savedEndpoint: savedEndpoint).defaultModel
    return defaultModel.isEmpty ? "text-embedding-3-small" : defaultModel
}

func embeddingPayload(option: EmbeddingEndpointOption, model: String, input: [String]) -> [String: Any] {
    var payload: [String: Any] = ["model": model, "input": input]
    for (key, value) in option.payloadExtras {
        payload[key] = value
    }
    return payload
}

func expectedSpeechReleaseAssetURL(fileName: String) -> String {
    "https://github.com/dowellhz/LeafReader/releases/download/\(SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag)/\(fileName)"
}

struct EmbeddingKeyStore {
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

func withIsolatedAISettingsDefaults(_ body: (UserDefaults) throws -> Void) throws {
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

