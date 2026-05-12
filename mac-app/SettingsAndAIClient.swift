import Cocoa
import CryptoKit
import Foundation

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class APIKeySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "v":
            pasteFromClipboard(into: editor)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func pasteFromClipboard(into editor: NSText) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: text)
    }
}

final class APIKeyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "c":
            copySelection(from: editor)
            return true
        case "x":
            copySelection(from: editor)
            editor.delete(nil)
            return true
        case "v":
            pasteFromClipboard(into: editor)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func copySelection(from editor: NSText) {
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
    }

    private func pasteFromClipboard(into editor: NSText) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: text)
    }
}

struct AIModelConfig {
    let id: String
    let provider: String
    let displayName: String
    let endpoint: URL
    let model: String
    let supportsThinkingToggle: Bool

    var usesAzureAPIKeyHeader: Bool {
        guard provider == AISettingsStore.customProviderID,
              let host = endpoint.host?.lowercased() else {
            return false
        }
        return host.hasSuffix(".openai.azure.com")
            || host.hasSuffix(".services.ai.azure.com")
            || host.hasSuffix(".cognitiveservices.azure.com")
    }

    var usesAzureDeploymentEndpoint: Bool {
        guard usesAzureAPIKeyHeader else { return false }
        return endpoint.path.lowercased().contains("/openai/deployments/")
    }

    var usesResponsesEndpoint: Bool {
        let path = endpoint.path.lowercased()
        return path.hasSuffix("/openai/responses") || path.hasSuffix("/openai/v1/responses")
    }
}

enum LocalEncryptedStore {
    static func string(forKey key: String) -> String {
        guard
            let encoded = UserDefaults.standard.string(forKey: key),
            let data = Data(base64Encoded: encoded),
            let sealedBox = try? AES.GCM.SealedBox(combined: data),
            let decrypted = try? AES.GCM.open(sealedBox, using: encryptionKey),
            let value = String(data: decrypted, encoding: .utf8)
        else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        if let sealedBox = try? AES.GCM.seal(Data(trimmed.utf8), using: encryptionKey),
           let combined = sealedBox.combined {
            UserDefaults.standard.set(combined.base64EncodedString(), forKey: key)
        }
    }

    private static var encryptionKey: SymmetricKey {
        let material = [
            "LeafReaderLocalEncryptedAPIKey",
            Bundle.main.bundleIdentifier ?? "com.linlu.leafreader",
            NSUserName(),
            NSHomeDirectory()
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }
}

enum AISettingsStore {
    static let selectedModelKey = "selectedAIModelID"
    static let customModelID = "custom"
    static let customProviderID = "custom"
    static let customEndpointKey = "customAIEndpointURL"
    static let customModelNameKey = "customAIModelName"
    private static let fallbackCustomEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    static let models: [AIModelConfig] = [
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

    static var selectedModel: AIModelConfig {
        let selectedID = UserDefaults.standard.string(forKey: selectedModelKey)
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

        if let legacyKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey(for: config.provider))?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyKey.isEmpty {
            LocalEncryptedStore.save(legacyKey, forKey: encryptedAPIKeyDefaultsKey(for: config.provider))
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey(for: config.provider))
            UserDefaults.standard.synchronize()
            return legacyKey
        }

        return ""
    }

    static func save(modelID: String, apiKey: String, customEndpoint: String = "", customModelName: String = "") {
        guard let model = models.first(where: { $0.id == modelID }) else { return }
        UserDefaults.standard.set(modelID, forKey: selectedModelKey)
        if modelID == customModelID {
            saveCustomEndpoint(customEndpoint)
            saveCustomModelName(customModelName)
        }
        LocalEncryptedStore.save(apiKey, forKey: encryptedAPIKeyDefaultsKey(for: model.provider))
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey(for: model.provider))
        UserDefaults.standard.synchronize()
    }

    static func apiKeyDefaultsKey(for provider: String) -> String {
        "apiKey.\(provider)"
    }

    static func encryptedAPIKeyDefaultsKey(for provider: String) -> String {
        "encryptedApiKey.\(provider)"
    }

    static var customEndpointString: String {
        UserDefaults.standard.string(forKey: customEndpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackCustomEndpoint.absoluteString
    }

    static var customModelName: String {
        let saved = UserDefaults.standard.string(forKey: customModelNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "custom-model" : saved
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
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if validEndpoint(from: trimmed) != nil {
            UserDefaults.standard.set(trimmed, forKey: customEndpointKey)
        } else if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: customEndpointKey)
        }
    }

    private static func saveCustomModelName(_ modelName: String) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: customModelNameKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: customModelNameKey)
        }
    }

    private static func validEndpoint(from string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

final class AIClient {

    func send(messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        Self.configureHeaders(for: config, apiKey: apiKey, request: &request)
        let payload = Self.payload(for: config, messages: messages, stream: false)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(NSError(domain: config.provider, code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "\(config.displayName) HTTP \(http.statusCode): \(body)"
                ])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: config.provider, code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No response data"
                ])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let content = Self.responseText(from: json, provider: config.provider) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected response: \(body)"
                    ])
                }
                completion(.success(Self.visibleAnswer(from: content)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func sendStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        Self.configureHeaders(for: config, apiKey: apiKey, request: &request)
        let payload = Self.payload(for: config, messages: messages, stream: true)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        Task {
            var fullText = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: config.provider, code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response"
                    ])
                }
                guard (200...299).contains(http.statusCode) else {
                    var body = ""
                    for try await line in bytes.lines {
                        body += line
                    }
                    throw NSError(domain: config.provider, code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "\(config.displayName) HTTP \(http.statusCode): \(body)"
                    ])
                }

                for try await line in bytes.lines {
                    guard let delta = Self.deltaText(fromStreamLine: line, provider: config.provider), !delta.isEmpty else { continue }
                    fullText += delta
                    onDelta(delta)
                }

                completion(.success(Self.visibleAnswer(from: fullText)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func configureHeaders(for config: AIModelConfig, apiKey: String, request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.provider == "claude" {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if config.usesAzureAPIKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func payload(for config: AIModelConfig, messages: [ChatMessage], stream: Bool) -> [String: Any] {
        if config.usesResponsesEndpoint {
            var payload: [String: Any] = [
                "model": config.model,
                "input": responsesInput(from: messages),
                "max_output_tokens": 2048
            ]
            let instructions = messages
                .filter { $0.role == "system" }
                .map(\.content)
                .joined(separator: "\n\n")
            if !instructions.isEmpty {
                payload["instructions"] = instructions
            }
            if stream {
                payload["stream"] = true
            }
            return payload
        }

        if config.provider == "claude" {
            let system = messages
                .filter { $0.role == "system" }
                .map(\.content)
                .joined(separator: "\n\n")
            let claudeMessages = messages
                .filter { $0.role != "system" }
                .map { message in
                    [
                        "role": message.role == "assistant" ? "assistant" : "user",
                        "content": [["type": "text", "text": message.content]]
                    ] as [String: Any]
                }
            var payload: [String: Any] = [
                "model": config.model,
                "max_tokens": 2048,
                "messages": claudeMessages,
                "stream": stream
            ]
            if !system.isEmpty {
                payload["system"] = system
            }
            return payload
        }

        var payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.4,
            "max_tokens": 2048
        ]
        if !config.usesAzureDeploymentEndpoint {
            payload["model"] = config.model
        }
        if stream {
            payload["stream"] = true
        }
        if config.supportsThinkingToggle {
            payload["thinking"] = ["type": "disabled"]
        }
        return payload
    }

    private static func responsesInput(from messages: [ChatMessage]) -> String {
        messages
            .filter { $0.role != "system" }
            .map { message in
                let label = message.role == "assistant" ? "Assistant" : "User"
                return "\(label):\n\(message.content)"
            }
            .joined(separator: "\n\n")
    }

    private static func responseText(from json: [String: Any]?, provider: String) -> String? {
        guard let json else { return nil }
        if provider == "claude" {
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { block in
                block["text"] as? String
            }.joined()
        }

        if let outputText = json["output_text"] as? String {
            return outputText
        }
        if let output = json["output"] as? [[String: Any]] {
            let text = output.compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else { return nil }
                return content.compactMap { block in
                    (block["text"] as? String) ?? (block["content"] as? String)
                }.joined()
            }.joined()
            if !text.isEmpty {
                return text
            }
        }

        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }

    private static func deltaText(fromStreamLine line: String, provider: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonString: String
        if trimmed.hasPrefix("data:") {
            jsonString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonString = trimmed
        }
        if jsonString == "[DONE]" { return nil }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let type = json["type"] as? String, type == "response.output_text.delta" {
            return json["delta"] as? String
        }
        if let type = json["type"] as? String, type == "response.completed" {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
            if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
                return content
            }
            if let delta = first["delta"] as? [String: Any],
               delta["reasoning_content"] as? String != nil {
                return nil
            }
            if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
            if let message = first["message"] as? [String: Any],
               message["reasoning_content"] as? String != nil {
                return nil
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if provider == "claude",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }

        if json["reasoning_content"] as? String != nil {
            return nil
        }
        if let content = json["content"] as? String {
            return content
        }
        return nil
    }

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }

    static func visibleAnswer(from content: String) -> String {
        content
            .replacingOccurrences(of: #"(?s)<think>.*?(</think>|$)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<reasoning>.*?(</reasoning>|$)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
