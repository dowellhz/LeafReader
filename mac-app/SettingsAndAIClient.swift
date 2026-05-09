import Cocoa
import CryptoKit
import Foundation

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class APIKeySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteFromClipboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}

final class APIKeyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteFromClipboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}

struct AIModelConfig {
    let id: String
    let provider: String
    let displayName: String
    let endpoint: URL
    let model: String
    let supportsThinkingToggle: Bool
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
        )
    ]

    static var selectedModel: AIModelConfig {
        let selectedID = UserDefaults.standard.string(forKey: selectedModelKey)
        return models.first { $0.id == selectedID } ?? models[0]
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

    static func save(modelID: String, apiKey: String) {
        guard let model = models.first(where: { $0.id == modelID }) else { return }
        UserDefaults.standard.set(modelID, forKey: selectedModelKey)
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
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func payload(for config: AIModelConfig, messages: [ChatMessage], stream: Bool) -> [String: Any] {
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
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.4,
            "max_tokens": 2048
        ]
        if stream {
            payload["stream"] = true
        }
        if config.supportsThinkingToggle {
            payload["thinking"] = ["type": "disabled"]
        }
        return payload
    }

    private static func responseText(from json: [String: Any]?, provider: String) -> String? {
        guard let json else { return nil }
        if provider == "claude" {
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { block in
                block["text"] as? String
            }.joined()
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
