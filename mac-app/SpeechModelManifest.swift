import Foundation

struct SpeechModelManifest: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64?
        let sha256: String
    }

    let generatedAt: String?
    let assets: [Asset]

    func sha256(for fileName: String) -> String? {
        assets.first { $0.name == fileName }?.sha256
    }
}

extension SpeechRuntimeResourceManager {
    static func decodeModelManifest(_ data: Data) throws -> SpeechModelManifest {
        try JSONDecoder().decode(SpeechModelManifest.self, from: data)
    }

    static func fetchModelManifest(completion: @escaping (Result<SpeechModelManifest?, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: Runtime.modelManifestURL) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            if statusCode == 404 {
                completion(.success(nil))
                return
            }
            guard (200...299).contains(statusCode), let data else {
                completion(.failure(NSError(
                    domain: downloadErrorDomain,
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型校验清单下载失败，请稍后重试。", "Model checksum manifest download failed. Please try again later.")]
                )))
                return
            }

            do {
                completion(.success(try decodeModelManifest(data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
