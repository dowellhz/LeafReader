import Foundation

extension AISettingsStore {
    struct EmbeddingEndpointOption {
        let id: String
        let title: String
        let endpoint: String
        let defaultModel: String
        let requiresAPIKey: Bool
        let maxInputCharacters: Int
        let payloadExtras: [String: String]
        let providerDescriptor: AIProviderDescriptor

        init(
            id: String,
            title: String,
            endpoint: String,
            defaultModel: String,
            requiresAPIKey: Bool = true,
            maxInputCharacters: Int = 6000,
            payloadExtras: [String: String] = [:]
        ) {
            self.id = id
            self.title = title
            self.endpoint = endpoint
            self.defaultModel = defaultModel
            self.requiresAPIKey = requiresAPIKey
            self.maxInputCharacters = maxInputCharacters
            self.payloadExtras = payloadExtras
            self.providerDescriptor = AIProviderDescriptor.embeddingProvider(id: id, displayName: title)
        }
    }

    static let embeddingProviderID = "embedding"
    static let embeddingEndpointKey = "embeddingEndpointURL"
    static let embeddingModelNameKey = "embeddingModelName"
    static let fallbackEmbeddingModelName = "text-embedding-3-small"
    static let customEmbeddingEndpointID = "other"
    private static let fallbackEmbeddingEndpoint = URL(string: "https://api.openai.com/v1/embeddings")!

    static var embeddingEndpointOptions: [EmbeddingEndpointOption] {
        [
            EmbeddingEndpointOption(id: "openai", title: AppText.localized("OpenAI 向量", "OpenAI Embeddings"), endpoint: "https://api.openai.com/v1/embeddings", defaultModel: "text-embedding-3-small"),
            EmbeddingEndpointOption(id: "jina", title: AppText.localized("Jina AI 向量", "Jina AI Embeddings"), endpoint: "https://api.jina.ai/v1/embeddings", defaultModel: "jina-embeddings-v3"),
            EmbeddingEndpointOption(id: "voyage", title: AppText.localized("Voyage AI 向量", "Voyage AI Embeddings"), endpoint: "https://api.voyageai.com/v1/embeddings", defaultModel: "voyage-3-large"),
            EmbeddingEndpointOption(id: "siliconflow", title: AppText.localized("硅基流动向量", "SiliconFlow Embeddings"), endpoint: "https://api.siliconflow.cn/v1/embeddings", defaultModel: "Qwen/Qwen3-Embedding-8B", payloadExtras: ["encoding_format": "float"]),
            EmbeddingEndpointOption(id: "dashscope", title: AppText.localized("阿里云百炼向量", "Alibaba DashScope Embeddings"), endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings", defaultModel: "text-embedding-v4"),
            EmbeddingEndpointOption(id: "ollama", title: AppText.localized("Ollama 本地向量", "Ollama Local Embeddings"), endpoint: "http://127.0.0.1:11434/api/embed", defaultModel: "nomic-embed-text", requiresAPIKey: false),
            EmbeddingEndpointOption(id: "lmstudio", title: AppText.localized("LM Studio 本地向量", "LM Studio Local Embeddings"), endpoint: "http://127.0.0.1:1234/v1/embeddings", defaultModel: "text-embedding-nomic-embed-text-v1.5", requiresAPIKey: false),
            EmbeddingEndpointOption(id: "llamacpp", title: AppText.localized("llama.cpp 本地向量", "llama.cpp Local Embeddings"), endpoint: "http://127.0.0.1:8080/v1/embeddings", defaultModel: "nomic-embed-text", requiresAPIKey: false),
            EmbeddingEndpointOption(id: customEmbeddingEndpointID, title: AppText.localized("其他", "Other"), endpoint: "", defaultModel: "")
        ]
    }

    static var embeddingEndpointString: String {
        trimmedStoredString(forKey: embeddingEndpointKey) ?? fallbackEmbeddingEndpoint.absoluteString
    }

    static var embeddingModelName: String {
        if let saved = nonEmptyTrimmed(defaults.string(forKey: embeddingModelNameKey)) {
            return saved
        }
        return nonEmptyTrimmed(selectedEmbeddingEndpointOption.defaultModel) ?? fallbackEmbeddingModelName
    }

    static var embeddingEndpoint: URL {
        validEndpoint(from: embeddingEndpointString) ?? fallbackEmbeddingEndpoint
    }

    static var selectedEmbeddingEndpointOption: EmbeddingEndpointOption {
        let savedEndpoint = embeddingEndpointString
        if let option = embeddingEndpointOptions.first(where: { $0.endpoint == savedEndpoint }) {
            return option
        }
        if savedEndpoint == "https://api.siliconflow.com/v1/embeddings",
           let legacyOption = embeddingEndpointOptions.first(where: { $0.id == "siliconflow" })
            ?? embeddingEndpointOptions.last {
            return legacyOption
        }
        let customRequiresKey = !(validEndpoint(from: savedEndpoint)?.isLocalEndpoint ?? false)
        return EmbeddingEndpointOption(
            id: customEmbeddingEndpointID,
            title: AppText.localized("其他", "Other"),
            endpoint: savedEndpoint,
            defaultModel: "",
            requiresAPIKey: customRequiresKey
        )
    }

    static var selectedEmbeddingProviderDescriptor: AIProviderDescriptor {
        selectedEmbeddingEndpointOption.providerDescriptor
    }

    static var embeddingAPIKey: String {
        embeddingAPIKeyMigratingLegacyIfNeeded(for: selectedEmbeddingEndpointOption.id)
    }

    static func embeddingAPIKey(for optionID: String) -> String {
        let providerKey = embeddingAPIKeyProviderID(for: optionID)
        let key = LocalEncryptedStore.string(forKey: encryptedAPIKeyDefaultsKey(for: providerKey))
        if !key.isEmpty {
            return key
        }

        return ""
    }

    static func embeddingAPIKeyMigratingLegacyIfNeeded(for optionID: String) -> String {
        let providerKey = embeddingAPIKeyProviderID(for: optionID)
        let key = LocalEncryptedStore.string(forKey: encryptedAPIKeyDefaultsKey(for: providerKey))
        if !key.isEmpty {
            return key
        }

        let legacyProviderKey = LocalEncryptedStore.string(forKey: encryptedAPIKeyDefaultsKey(for: embeddingProviderID))
        if !legacyProviderKey.isEmpty {
            LocalEncryptedStore.save(legacyProviderKey, forKey: encryptedAPIKeyDefaultsKey(for: providerKey))
            LocalEncryptedStore.save("", forKey: encryptedAPIKeyDefaultsKey(for: embeddingProviderID))
            defaults.synchronize()
            return legacyProviderKey
        }

        if let legacyKey = nonEmptyTrimmed(defaults.string(forKey: apiKeyDefaultsKey(for: embeddingProviderID))) {
            LocalEncryptedStore.save(legacyKey, forKey: encryptedAPIKeyDefaultsKey(for: providerKey))
            defaults.removeObject(forKey: apiKeyDefaultsKey(for: embeddingProviderID))
            defaults.synchronize()
            return legacyKey
        }

        return ""
    }

    static func saveEmbedding(endpoint: String, modelName: String, apiKey: String, optionID: String? = nil) {
        let endpointValue = trimmed(endpoint)
        if validEndpoint(from: endpointValue) != nil {
            defaults.set(endpointValue, forKey: embeddingEndpointKey)
        } else if endpointValue.isEmpty {
            defaults.removeObject(forKey: embeddingEndpointKey)
        }

        let modelValue = trimmed(modelName)
        if modelValue.isEmpty {
            defaults.removeObject(forKey: embeddingModelNameKey)
        } else {
            defaults.set(modelValue, forKey: embeddingModelNameKey)
        }

        let selectedOptionID = optionID ?? selectedEmbeddingEndpointOption.id
        LocalEncryptedStore.save(apiKey, forKey: encryptedAPIKeyDefaultsKey(for: embeddingAPIKeyProviderID(for: selectedOptionID)))
        defaults.removeObject(forKey: apiKeyDefaultsKey(for: embeddingProviderID))
        defaults.synchronize()
    }

    private static func embeddingAPIKeyProviderID(for optionID: String) -> String {
        "\(embeddingProviderID).\(optionID)"
    }
}
