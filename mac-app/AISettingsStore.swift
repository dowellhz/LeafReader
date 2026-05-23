import Cocoa
import Foundation

enum AISettingsStore {
    enum SpeechLanguageHint {
        case english
        case chinese
    }

    struct EmbeddingEndpointOption {
        let id: String
        let title: String
        let endpoint: String
        let defaultModel: String
        let requiresAPIKey: Bool
        let maxInputCharacters: Int
        let payloadExtras: [String: String]

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
        }
    }

    static let selectedModelKey = "selectedAIModelID"
    static let customModelID = "custom"
    static let customProviderID = "custom"
    static let customEndpointKey = "customAIEndpointURL"
    static let customModelNameKey = "customAIModelName"
    static let embeddingProviderID = "embedding"
    static let embeddingEndpointKey = "embeddingEndpointURL"
    static let embeddingModelNameKey = "embeddingModelName"
    static let autoEmbeddingIndexEnabledKey = "autoEmbeddingIndexEnabled"
    static let speakSelectedWordEnabledKey = "speakSelectedWordEnabled"
    static let saveAIConversationEnabledKey = "saveAIConversationEnabled"
    static let selectedSpeechRuntimeKey = "selectedSpeechRuntime"
    static let speechSpeedKey = "speechSpeed"
    static let kittenSpeechVoiceKey = "kittenSpeechVoice"
    static let kokoroSpeechVoiceKey = "kokoroSpeechVoice"
    private static let defaultSpeechRuntimeID = "kitten"
    private static let defaultSpeechSpeedID = "normal"
    static let defaultKittenSpeechVoiceID = "Jasper"
    static let defaultKokoroSpeechVoiceID = "af_heart"
    private static let validSpeechRuntimeIDs = Set(["kokoro", "kitten"])
    private static let validSpeechSpeedIDs = Set(["fast", "normal", "slow", "verySlow"])
    private static let validKittenSpeechVoiceIDs = Set(["Bella", "Jasper", "Luna", "Bruno", "Rosie", "Hugo", "Kiki", "Leo"])
    private typealias SpeechVoiceDefinition = (zhTitle: String, enTitle: String, id: String)

    private static let kokoroEnglishSpeechVoiceDefinitions: [SpeechVoiceDefinition] = [
        ("美国女声 Bella", "American Female Bella", "af_bella"),
        ("美国女声 Heart", "American Female Heart", "af_heart"),
        ("美国男声 Adam", "American Male Adam", "am_adam"),
        ("美国男声 Michael", "American Male Michael", "am_michael"),
        ("英国女声 Emma", "British Female Emma", "bf_emma"),
        ("英国女声 Isabella", "British Female Isabella", "bf_isabella"),
        ("英国男声 George", "British Male George", "bm_george"),
        ("英国男声 Lewis", "British Male Lewis", "bm_lewis")
    ]
    static let kokoroEnglishSpeechVoiceIDs = Set(
        kokoroEnglishSpeechVoiceDefinitions.map { $0.id }
    )
    private static let kokoroChineseSpeechVoiceDefinitions: [SpeechVoiceDefinition] = [
        ("中文女声 1", "Chinese Female 1", "zf_001"),
        ("中文女声 2", "Chinese Female 2", "zf_002"),
        ("中文女声 3", "Chinese Female 3", "zf_003"),
        ("中文女声 4", "Chinese Female 4", "zf_004"),
        ("中文女声 5", "Chinese Female 5", "zf_005"),
        ("中文男声 1", "Chinese Male 1", "zm_009"),
        ("中文男声 2", "Chinese Male 2", "zm_010"),
        ("中文男声 3", "Chinese Male 3", "zm_011"),
        ("中文男声 4", "Chinese Male 4", "zm_012"),
        ("浑厚男", "Deep Male", "zm_013"),
        ("Maple", "Maple", "af_maple"),
        ("Sol", "Sol", "af_sol"),
        ("Vale", "Vale", "bf_vale")
    ]
    static let kokoroChineseSpeechVoiceIDs = Set(
        kokoroChineseSpeechVoiceDefinitions.map { $0.id }
    )
    private static let validKokoroSpeechVoiceIDs = Set(
        (kokoroEnglishSpeechVoiceDefinitions + kokoroChineseSpeechVoiceDefinitions).map { $0.id }
    )
    private static var defaults: UserDefaults = .standard
    private static let fallbackCustomEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let fallbackEmbeddingEndpoint = URL(string: "https://api.openai.com/v1/embeddings")!
    static let fallbackEmbeddingModelName = "text-embedding-3-small"
    static let customEmbeddingEndpointID = "other"
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
        !apiKey(for: selectedModel).isEmpty
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
        if savedEndpoint == "https://api.siliconflow.com/v1/embeddings" {
            return embeddingEndpointOptions.first { $0.id == "siliconflow" } ?? embeddingEndpointOptions.last!
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

    static var selectedSpeechRuntimeID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: selectedSpeechRuntimeKey)) ?? defaultSpeechRuntimeID
        return validSpeechRuntimeIDs.contains(value) ? value : defaultSpeechRuntimeID
    }

    static func saveSelectedSpeechRuntimeID(_ id: String) {
        guard validSpeechRuntimeIDs.contains(id) else { return }
        defaults.set(id, forKey: selectedSpeechRuntimeKey)
        defaults.synchronize()
    }

    static var selectedSpeechSpeedID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: speechSpeedKey)) ?? defaultSpeechSpeedID
        return validSpeechSpeedIDs.contains(value) ? value : defaultSpeechSpeedID
    }

    static var speechSpeedOptions: [(title: String, id: String)] {
        [
            (AppText.localized("快", "Fast"), "fast"),
            (AppText.localized("正常", "Normal"), "normal"),
            (AppText.localized("慢", "Slow"), "slow"),
            (AppText.localized("非常慢", "Very Slow"), "verySlow")
        ]
    }

    static var kittenSpeechVoiceOptions: [(title: String, id: String)] {
        ["Bella", "Jasper", "Luna", "Bruno", "Rosie", "Hugo", "Kiki", "Leo"].map { ($0, $0) }
    }

    static var kokoroSpeechVoiceOptions: [(title: String, id: String)] {
        kokoroSpeechVoiceOptions(languageHint: nil)
    }

    static func kokoroSpeechVoiceOptions(languageHint: SpeechLanguageHint?) -> [(title: String, id: String)] {
        let englishOptions = localizedSpeechVoiceOptions(kokoroEnglishSpeechVoiceDefinitions)
        let chineseOptions = localizedSpeechVoiceOptions(kokoroChineseSpeechVoiceDefinitions)
        let availableIDs = availableKokoroSpeechVoiceIDs()
        let installedChineseOptions = availableIDs.isEmpty
            ? chineseOptions
            : chineseOptions.filter { availableIDs.contains($0.id) }
        switch languageHint {
        case .english:
            return englishOptions
        case .chinese:
            return installedChineseOptions
        case .none:
            return englishOptions + installedChineseOptions
        }
    }

    static func speechVoiceOptions(runtimeID: String?) -> [(title: String, id: String)] {
        isKokoroSpeechRuntime(runtimeID) ? kokoroSpeechVoiceOptions : kittenSpeechVoiceOptions
    }

    static func speechVoiceOptions(runtimeID: String?, languageHint: SpeechLanguageHint?) -> [(title: String, id: String)] {
        isKokoroSpeechRuntime(runtimeID) ? kokoroSpeechVoiceOptions(languageHint: languageHint) : kittenSpeechVoiceOptions
    }

    static func selectedSpeechVoiceID(runtimeID: String?) -> String {
        isKokoroSpeechRuntime(runtimeID) ? selectedKokoroSpeechVoiceID : selectedKittenSpeechVoiceID
    }

    static func selectedKokoroSpeechVoiceID(languageHint: SpeechLanguageHint?) -> String {
        let selected = selectedKokoroSpeechVoiceID
        let options = kokoroSpeechVoiceOptions(languageHint: languageHint)
        if options.contains(where: { $0.id == selected }) {
            return selected
        }
        return options.first?.id ?? defaultKokoroSpeechVoiceID
    }

    static func speechVoiceTitle(for id: String, runtimeID: String?) -> String {
        speechVoiceOptions(runtimeID: runtimeID).first { $0.id == id }?.title ?? id
    }

    private static func isKokoroSpeechRuntime(_ runtimeID: String?) -> Bool {
        runtimeID == SpeechRuntimeResourceManager.Runtime.kokoro.id
    }

    private static func localizedSpeechVoiceOptions(_ definitions: [SpeechVoiceDefinition]) -> [(title: String, id: String)] {
        definitions.map {
            (title: AppText.localized($0.zhTitle, $0.enTitle), id: $0.id)
        }
    }

    private static func availableKokoroSpeechVoiceIDs() -> Set<String> {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml", isDirectory: true)
        let candidates = [
            root.appendingPathComponent("ANE", isDirectory: true),
            root.appendingPathComponent("ANE-zh/voices", isDirectory: true)
        ]
        var ids = Set<String>()
        for directory in candidates {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for url in contents where url.pathExtension == "bin" {
                ids.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return ids
    }

    static var selectedKittenSpeechVoiceID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: kittenSpeechVoiceKey)) ?? defaultKittenSpeechVoiceID
        return validKittenSpeechVoiceIDs.contains(value) ? value : defaultKittenSpeechVoiceID
    }

    static var selectedKokoroSpeechVoiceID: String {
        let value = nonEmptyTrimmed(defaults.string(forKey: kokoroSpeechVoiceKey)) ?? defaultKokoroSpeechVoiceID
        return validKokoroSpeechVoiceIDs.contains(value) ? value : defaultKokoroSpeechVoiceID
    }

    static func saveKittenSpeechVoiceID(_ id: String) {
        guard validKittenSpeechVoiceIDs.contains(id) else { return }
        defaults.set(id, forKey: kittenSpeechVoiceKey)
        defaults.synchronize()
    }

    static func saveKokoroSpeechVoiceID(_ id: String) {
        guard validKokoroSpeechVoiceIDs.contains(id) else { return }
        defaults.set(id, forKey: kokoroSpeechVoiceKey)
        defaults.synchronize()
    }

    static func saveSpeechVoiceID(_ id: String, runtimeID: String?) {
        if isKokoroSpeechRuntime(runtimeID) {
            saveKokoroSpeechVoiceID(id)
        } else {
            saveKittenSpeechVoiceID(id)
        }
    }

    static func saveSpeechSpeedID(_ id: String) {
        guard validSpeechSpeedIDs.contains(id) else { return }
        defaults.set(id, forKey: speechSpeedKey)
        defaults.synchronize()
    }

    static var kittenSpeechSpeedMultiplier: Double {
        switch selectedSpeechSpeedID {
        case "fast": return 1.25
        case "slow": return 0.82
        case "verySlow": return 0.65
        default: return 1.0
        }
    }

    static var kokoroSpeechSpeedMultiplier: Double {
        switch selectedSpeechSpeedID {
        case "fast": return 1.25
        case "slow": return 0.82
        case "verySlow": return 0.7
        default: return 1.0
        }
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

    private static func validEndpoint(from string: String) -> URL? {
        let endpointValue = trimmed(string)
        guard let url = URL(string: endpointValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmptyTrimmed(_ string: String?) -> String? {
        guard let value = string.map(trimmed), !value.isEmpty else { return nil }
        return value
    }

    private static func trimmedStoredString(forKey key: String) -> String? {
        defaults.string(forKey: key).map(trimmed)
    }
}

private extension URL {
    var isLocalEndpoint: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
