import Foundation

struct EmbeddingModelConfig {
    let provider: String
    let endpoint: URL
    let model: String
    let apiKey: String
    let requiresAPIKey: Bool
    let maxInputCharacters: Int
    let payloadExtras: [String: String]

    var cacheModelID: String {
        "\(provider):\(model):\(endpoint.absoluteString)"
    }
}

final class EmbeddingClient {
    static func configFromCurrentAISettings() -> EmbeddingModelConfig? {
        let endpoint = AISettingsStore.embeddingEndpoint
        let endpointOption = AISettingsStore.selectedEmbeddingEndpointOption
        let apiKey = AISettingsStore.embeddingAPIKey
        guard !endpointOption.requiresAPIKey || !apiKey.isEmpty else { return nil }

        return EmbeddingModelConfig(
            provider: endpointOption.id,
            endpoint: endpoint,
            model: AISettingsStore.embeddingModelName,
            apiKey: apiKey,
            requiresAPIKey: endpointOption.requiresAPIKey,
            maxInputCharacters: endpointOption.maxInputCharacters,
            payloadExtras: endpointOption.payloadExtras
        )
    }

    func embed(texts: [String], config: EmbeddingModelConfig, completion: @escaping (Result<[[Float]], Error>) -> Void) {
        let cleanedTexts = texts.map { String($0.prefix(config.maxInputCharacters)) }
        guard !cleanedTexts.isEmpty else {
            completion(.success([]))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload = requestPayload(texts: cleanedTexts, config: config)

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
                guard let embeddings = self.parseEmbeddings(from: json, expectedCount: cleanedTexts.count, config: config) else {
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected embedding response"
                    ])
                }
                completion(.success(embeddings))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func requestPayload(texts: [String], config: EmbeddingModelConfig) -> [String: Any] {
        if config.endpoint.path.lowercased() == "/api/embed" {
            return [
                "model": config.model,
                "input": texts
            ]
        }

        var payload: [String: Any] = [
            "model": config.model,
            "input": texts
        ]
        for (key, value) in config.payloadExtras {
            payload[key] = value
        }
        return payload
    }

    private func parseEmbeddings(from json: [String: Any]?, expectedCount: Int, config: EmbeddingModelConfig) -> [[Float]]? {
        if let rows = json?["data"] as? [[String: Any]] {
            let sortedRows = rows.sorted {
                (($0["index"] as? Int) ?? 0) < (($1["index"] as? Int) ?? 0)
            }
            let embeddings = sortedRows.compactMap { row -> [Float]? in
                normalizedFloatArray(row["embedding"])
            }
            return embeddings.count == expectedCount ? embeddings : nil
        }

        if let values = json?["embeddings"] as? [[Double]] {
            let embeddings = values.map { $0.map(Float.init) }
            return embeddings.count == expectedCount ? embeddings : nil
        }

        if let values = json?["embeddings"] as? [[Float]] {
            return values.count == expectedCount ? values : nil
        }

        if expectedCount == 1, let embedding = normalizedFloatArray(json?["embedding"]) {
            return [embedding]
        }

        return nil
    }

    private func normalizedFloatArray(_ value: Any?) -> [Float]? {
        if let values = value as? [Double] {
            return values.map(Float.init)
        }
        if let values = value as? [Float] {
            return values
        }
        if let values = value as? [NSNumber] {
            return values.map { $0.floatValue }
        }
        return nil
    }
}
