import Foundation

final class AIClient {

    @discardableResult
    func send(messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return nil
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
            return nil
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(NSError(domain: config.provider, code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: NetworkErrorFormatter.httpErrorDescription(
                        prefix: config.displayName,
                        statusCode: http.statusCode,
                        body: body
                    )
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
                guard let content = AIResponseParser.responseText(from: json, provider: config.provider) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected response: \(body)"
                    ])
                }
                completion(.success(AIResponseTextFormatter.visibleAnswer(content)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    @discardableResult
    func sendStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>? {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return nil
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
            return nil
        }

        let task = Task {
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
                        if body.count > 8192 {
                            break
                        }
                    }
                    throw NSError(domain: config.provider, code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: NetworkErrorFormatter.httpErrorDescription(
                            prefix: config.displayName,
                            statusCode: http.statusCode,
                            body: body
                        )
                    ])
                }

                for try await line in bytes.lines {
                    guard let delta = AIResponseParser.deltaText(fromStreamLine: line, provider: config.provider), !delta.isEmpty else { continue }
                    fullText += delta
                    onDelta(delta)
                }

                completion(.success(AIResponseTextFormatter.visibleAnswer(fullText)))
            } catch {
                completion(.failure(error))
            }
        }
        return task
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

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }

}
