import Foundation

final class AIClient {

    @discardableResult
    func send(messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !config.requiresAPIKey || !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return nil
        }

        let request: URLRequest
        do {
            request = try AIChatRequestBuilder.request(
                for: config,
                apiKey: apiKey,
                messages: messages,
                stream: false
            )
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
                guard let content = AIChatResponseDecoder.responseText(from: json, config: config) else {
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
        guard !config.requiresAPIKey || !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return nil
        }

        let request: URLRequest
        do {
            request = try AIChatRequestBuilder.request(
                for: config,
                apiKey: apiKey,
                messages: messages,
                stream: true
            )
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
                    guard let delta = AIChatResponseDecoder.deltaText(fromStreamLine: line, config: config), !delta.isEmpty else { continue }
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

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }

}
