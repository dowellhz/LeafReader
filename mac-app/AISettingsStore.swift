import Cocoa
import Foundation

enum AISettingsStore {
    enum SpeechLanguageHint {
        case english
        case chinese
    }

    static let selectedModelKey = "selectedAIModelID"
    static let customModelID = "custom"
    static let customProviderID = "custom"
    static let ollamaModelID = "ollama"
    static let ollamaProviderID = "ollama"
    static let localOpenAIModelID = "local-openai"
    static let localOpenAIProviderID = "local-openai"
    static let customEndpointKey = "customAIEndpointURL"
    static let customModelNameKey = "customAIModelName"
    static let ollamaModelNameKey = "ollamaModelName"
    static let localOpenAIEndpointKey = "localOpenAIEndpointURL"
    static let localOpenAIModelNameKey = "localOpenAIModelName"
    static let autoEmbeddingIndexEnabledKey = "autoEmbeddingIndexEnabled"
    static let speakSelectedWordEnabledKey = "speakSelectedWordEnabled"
    static let saveAIConversationEnabledKey = "saveAIConversationEnabled"
    static var defaults: UserDefaults = .standard
    private static let fallbackCustomEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    static func withDefaults<T>(_ defaults: UserDefaults, perform work: () throws -> T) rethrows -> T {
        let previousDefaults = self.defaults
        self.defaults = defaults
        defer { self.defaults = previousDefaults }
        return try work()
    }

    static var models: [AIModelConfig] {
        [
            AIModelConfig(
                id: "deepseek-v4-flash",
                provider: "deepseek",
                displayName: "DeepSeek V4 Flash",
                endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
                model: "deepseek-v4-flash",
                supportsThinkingToggle: true
            ),
            AIModelConfig(
                id: "deepseek-v4-pro",
                provider: "deepseek",
                displayName: "DeepSeek V4 Pro",
                endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
                model: "deepseek-v4-pro",
                supportsThinkingToggle: true
            ),
            AIModelConfig(
                id: "minimax-m2-7",
                provider: "minimax",
                displayName: "MiniMax M2.7",
                endpoint: URL(string: "https://api.minimaxi.com/v1/chat/completions")!,
                model: "MiniMax-M2.7",
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: "openai-gpt-4o",
                provider: "openai",
                displayName: "OpenAI GPT-4o",
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                model: "gpt-4o",
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: "openai-gpt-4-1",
                provider: "openai",
                displayName: "OpenAI GPT-4.1",
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                model: "gpt-4.1",
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: "claude-3-5-sonnet",
                provider: "claude",
                displayName: "Claude 3.5 Sonnet",
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                model: "claude-3-5-sonnet-latest",
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: "claude-3-5-haiku",
                provider: "claude",
                displayName: "Claude 3.5 Haiku",
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                model: "claude-3-5-haiku-latest",
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: ollamaModelID,
                provider: ollamaProviderID,
                displayName: "Ollama",
                endpoint: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
                model: ollamaModelName,
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: localOpenAIModelID,
                provider: localOpenAIProviderID,
                displayName: AppText.localized("本地 OpenAI 兼容", "Local OpenAI Compatible"),
                endpoint: localOpenAIEndpoint,
                model: localOpenAIModelName,
                supportsThinkingToggle: false
            ),
            AIModelConfig(
                id: customModelID,
                provider: customProviderID,
                displayName: AppText.localized("其他", "Other"),
                endpoint: fallbackCustomEndpoint,
                model: "custom-model",
                supportsThinkingToggle: false
            )
        ]
    }

    static var selectedModel: AIModelConfig {
        let selectedID = defaults.string(forKey: selectedModelKey)
        let model = models.first { $0.id == selectedID } ?? models[0]
        guard model.id == customModelID else { return model }
        return customModelConfig()
    }

    static var hasAPIKeyForSelectedModel: Bool {
        let model = selectedModel
        return !model.requiresAPIKey || !apiKey(for: model).isEmpty
    }

    static func apiKey(for config: AIModelConfig) -> String {
        let key = LocalEncryptedStore.string(forKey: encryptedAPIKeyDefaultsKey(for: config.provider))
        if !key.isEmpty {
            return key
        }

        if let legacyKey = nonEmptyTrimmed(defaults.string(forKey: apiKeyDefaultsKey(for: config.provider))) {
            LocalEncryptedStore.save(legacyKey, forKey: encryptedAPIKeyDefaultsKey(for: config.provider))
            defaults.removeObject(forKey: apiKeyDefaultsKey(for: config.provider))
            defaults.synchronize()
            return legacyKey
        }

        return ""
    }

    static func save(modelID: String, apiKey: String, customEndpoint: String = "", customModelName: String = "") {
        guard let model = models.first(where: { $0.id == modelID }) else { return }
        defaults.set(modelID, forKey: selectedModelKey)
        if modelID == customModelID {
            saveCustomEndpoint(customEndpoint)
            saveCustomModelName(customModelName)
        } else if modelID == ollamaModelID {
            saveOllamaModelName(customModelName)
        } else if modelID == localOpenAIModelID {
            saveLocalOpenAIEndpoint(customEndpoint)
            saveLocalOpenAIModelName(customModelName)
        }
        LocalEncryptedStore.save(apiKey, forKey: encryptedAPIKeyDefaultsKey(for: model.provider))
        defaults.removeObject(forKey: apiKeyDefaultsKey(for: model.provider))
        defaults.synchronize()
    }

    static func apiKeyDefaultsKey(for provider: String) -> String {
        "apiKey.\(provider)"
    }

    static func encryptedAPIKeyDefaultsKey(for provider: String) -> String {
        "encryptedApiKey.\(provider)"
    }

    static var customEndpointString: String {
        trimmedStoredString(forKey: customEndpointKey) ?? fallbackCustomEndpoint.absoluteString
    }

    static var customModelName: String {
        nonEmptyTrimmed(defaults.string(forKey: customModelNameKey)) ?? "custom-model"
    }

    static var ollamaModelName: String {
        nonEmptyTrimmed(defaults.string(forKey: ollamaModelNameKey)) ?? "llama3.1"
    }

    static var localOpenAIEndpointString: String {
        trimmedStoredString(forKey: localOpenAIEndpointKey) ?? "http://127.0.0.1:8000/v1/chat/completions"
    }

    static var localOpenAIEndpoint: URL {
        normalizedOpenAIChatEndpoint(from: localOpenAIEndpointString) ?? URL(string: "http://127.0.0.1:8000/v1/chat/completions")!
    }

    static var localOpenAIModelName: String {
        nonEmptyTrimmed(defaults.string(forKey: localOpenAIModelNameKey)) ?? "gemma-4-e4b-it-4bit"
    }

    static var autoEmbeddingIndexEnabled: Bool {
        defaults.bool(forKey: autoEmbeddingIndexEnabledKey)
    }

    static func saveAutoEmbeddingIndexEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: autoEmbeddingIndexEnabledKey)
        defaults.synchronize()
    }

    static var speakSelectedWordEnabled: Bool {
        if defaults.object(forKey: speakSelectedWordEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: speakSelectedWordEnabledKey)
    }

    static func saveSpeakSelectedWordEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: speakSelectedWordEnabledKey)
        defaults.synchronize()
    }

    static var saveAIConversationEnabled: Bool {
        defaults.bool(forKey: saveAIConversationEnabledKey)
    }

    static func saveAIConversationEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: saveAIConversationEnabledKey)
        defaults.synchronize()
    }

    static func customModelConfig() -> AIModelConfig {
        let endpoint = validEndpoint(from: customEndpointString) ?? fallbackCustomEndpoint
        return AIModelConfig(
            id: customModelID,
            provider: customProviderID,
            displayName: AppText.localized("其他", "Other"),
            endpoint: endpoint,
            model: customModelName,
            supportsThinkingToggle: false
        )
    }

    static func customValidationError(endpoint: String, modelName: String) -> String? {
        let trimmedEndpoint = trimmed(endpoint)
        let trimmedModelName = trimmed(modelName)
        if trimmedEndpoint.isEmpty {
            return AppText.localized("请输入自定义 URL。", "Enter a custom URL.")
        }
        if validEndpoint(from: trimmedEndpoint) == nil {
            return AppText.localized("自定义 URL 必须是有效的 http 或 https 地址。", "The custom URL must be a valid http or https address.")
        }
        if trimmedModelName.isEmpty {
            return AppText.localized("请输入模型 ID。", "Enter a model ID.")
        }
        return nil
    }

    static func ollamaValidationError(modelName: String) -> String? {
        if trimmed(modelName).isEmpty {
            return AppText.localized("请输入 Ollama 模型 ID。", "Enter an Ollama model ID.")
        }
        return nil
    }

    static func localOpenAIValidationError(endpoint: String, modelName: String) -> String? {
        let trimmedEndpoint = trimmed(endpoint)
        let trimmedModelName = trimmed(modelName)
        if trimmedEndpoint.isEmpty {
            return AppText.localized("请输入本地 OpenAI 兼容 URL。", "Enter a local OpenAI-compatible URL.")
        }
        guard normalizedOpenAIChatEndpoint(from: trimmedEndpoint) != nil else {
            return AppText.localized("本地 OpenAI 兼容 URL 必须是有效的 http 或 https 地址。", "The local OpenAI-compatible URL must be a valid http or https address.")
        }
        if trimmedModelName.isEmpty {
            return AppText.localized("请输入模型 ID。", "Enter a model ID.")
        }
        return nil
    }

    private static func saveCustomEndpoint(_ endpoint: String) {
        let endpointValue = trimmed(endpoint)
        if validEndpoint(from: endpointValue) != nil {
            defaults.set(endpointValue, forKey: customEndpointKey)
        } else if endpointValue.isEmpty {
            defaults.removeObject(forKey: customEndpointKey)
        }
    }

    private static func saveCustomModelName(_ modelName: String) {
        let modelValue = trimmed(modelName)
        if modelValue.isEmpty {
            defaults.removeObject(forKey: customModelNameKey)
        } else {
            defaults.set(modelValue, forKey: customModelNameKey)
        }
    }

    private static func saveOllamaModelName(_ modelName: String) {
        let modelValue = trimmed(modelName)
        if modelValue.isEmpty {
            defaults.removeObject(forKey: ollamaModelNameKey)
        } else {
            defaults.set(modelValue, forKey: ollamaModelNameKey)
        }
    }

    private static func saveLocalOpenAIEndpoint(_ endpoint: String) {
        let endpointValue = trimmed(endpoint)
        if let url = normalizedOpenAIChatEndpoint(from: endpointValue) {
            defaults.set(url.absoluteString, forKey: localOpenAIEndpointKey)
        } else if endpointValue.isEmpty {
            defaults.removeObject(forKey: localOpenAIEndpointKey)
        }
    }

    private static func saveLocalOpenAIModelName(_ modelName: String) {
        let modelValue = trimmed(modelName)
        if modelValue.isEmpty {
            defaults.removeObject(forKey: localOpenAIModelNameKey)
        } else {
            defaults.set(modelValue, forKey: localOpenAIModelNameKey)
        }
    }

    static func normalizedOpenAIChatEndpoint(from string: String) -> URL? {
        guard let url = validEndpoint(from: string) else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "v1" else { return url }
        return url.appendingPathComponent("chat/completions")
    }

    static func validEndpoint(from string: String) -> URL? {
        let endpointValue = trimmed(string)
        guard let url = URL(string: endpointValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    static func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nonEmptyTrimmed(_ string: String?) -> String? {
        guard let value = string.map(trimmed), !value.isEmpty else { return nil }
        return value
    }

    static func trimmedStoredString(forKey key: String) -> String? {
        defaults.string(forKey: key).map(trimmed)
    }
}

extension URL {
    var isLocalEndpoint: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
