import Foundation

enum AIChatRequestBuilder {
    static func request(
        for config: AIModelConfig,
        apiKey: String,
        messages: [ChatMessage],
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        configureHeaders(for: config, apiKey: apiKey, request: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(for: config, messages: messages, stream: stream))
        return request
    }

    static func configureHeaders(for config: AIModelConfig, apiKey: String, request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.providerDescriptor.chatRequestFormat == .anthropicMessages {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if config.usesAzureAPIKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    static func payload(for config: AIModelConfig, messages: [ChatMessage], stream: Bool) -> [String: Any] {
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

        if config.providerDescriptor.chatRequestFormat == .anthropicMessages {
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
}

enum AIChatResponseDecoder {
    static func responseText(from json: [String: Any]?, config: AIModelConfig) -> String? {
        AIResponseParser.responseText(from: json, provider: config.provider)
    }

    static func deltaText(fromStreamLine line: String, config: AIModelConfig) -> String? {
        AIResponseParser.deltaText(fromStreamLine: line, provider: config.provider)
    }
}
