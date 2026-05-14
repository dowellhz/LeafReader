import Foundation

struct EmbeddingModelConfig {
    let provider: String
    let endpoint: URL
    let model: String
    let apiKey: String

    var cacheModelID: String {
        "\(provider):\(model):\(endpoint.absoluteString)"
    }
}

final class EmbeddingClient {
    static func configFromCurrentAISettings() -> EmbeddingModelConfig? {
        let chatConfig = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: chatConfig)
        guard !apiKey.isEmpty else { return nil }

        if chatConfig.provider == "openai" {
            return EmbeddingModelConfig(
                provider: "openai",
                endpoint: AISettingsStore.embeddingEndpoint,
                model: AISettingsStore.embeddingModelName,
                apiKey: apiKey
            )
        }

        guard chatConfig.provider == AISettingsStore.customProviderID,
              chatConfig.endpoint.path.lowercased().contains("/chat/completions") else {
            return nil
        }

        return EmbeddingModelConfig(
            provider: AISettingsStore.customProviderID,
            endpoint: AISettingsStore.embeddingEndpoint,
            model: AISettingsStore.embeddingModelName,
            apiKey: apiKey
        )
    }

    func embed(texts: [String], config: EmbeddingModelConfig, completion: @escaping (Result<[[Float]], Error>) -> Void) {
        let cleanedTexts = texts.map { String($0.prefix(6000)) }
        guard !cleanedTexts.isEmpty else {
            completion(.success([]))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "model": config.model,
            "input": cleanedTexts
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(NSError(domain: config.provider, code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Embedding HTTP \(http.statusCode): \(body)"
                ])))
                return
            }

            guard let data else {
                completion(.failure(NSError(domain: config.provider, code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No embedding response data"
                ])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let rows = json?["data"] as? [[String: Any]] else {
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected embedding response"
                    ])
                }
                let sortedRows = rows.sorted {
                    (($0["index"] as? Int) ?? 0) < (($1["index"] as? Int) ?? 0)
                }
                let embeddings = sortedRows.compactMap { row -> [Float]? in
                    if let values = row["embedding"] as? [Double] {
                        return values.map(Float.init)
                    }
                    if let values = row["embedding"] as? [Float] {
                        return values
                    }
                    return nil
                }
                guard embeddings.count == cleanedTexts.count else {
                    throw NSError(domain: config.provider, code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Embedding count mismatch"
                    ])
                }
                completion(.success(embeddings))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
