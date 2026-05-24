import Foundation

struct SpeechModelManifest: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64?
        let sha256: String
    }

    let generatedAt: String?
    let assets: [Asset]

    func asset(named fileName: String) -> Asset? {
        assets.first { $0.name == fileName }
    }
}

extension SpeechRuntimeResourceManager {
    static func decodeModelManifest(_ data: Data) throws -> SpeechModelManifest {
        try JSONDecoder().decode(SpeechModelManifest.self, from: data)
    }

    static func bundledModelManifest() -> SpeechModelManifest? {
        guard let url = Bundle.main.url(forResource: "speech-models-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decodeModelManifest(data)
    }

    static func modelManifestDecodeResult(
        data: Data,
        bundledManifest: SpeechModelManifest?
    ) -> Result<SpeechModelManifest?, Error> {
        do {
            return .success(try decodeModelManifest(data))
        } catch {
            if let bundledManifest {
                NSLog(
                    "LeafReader speech model manifest: invalid remote manifest, using bundled manifest (%@)",
                    String(describing: error)
                )
                return .success(bundledManifest)
            }
            return .failure(error)
        }
    }

    static func fetchModelManifest(completion: @escaping (Result<SpeechModelManifest?, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: Runtime.modelManifestURL) { data, response, error in
            if let error {
                let bundledManifest = bundledModelManifest()
                NSLog(
                    "LeafReader speech model manifest: unavailable, using bundled manifest=%d (%@)",
                    bundledManifest != nil,
                    String(describing: error)
                )
                completion(.success(bundledManifest))
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            if statusCode == 404 {
                completion(.success(bundledModelManifest()))
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

            completion(modelManifestDecodeResult(data: data, bundledManifest: bundledModelManifest()))
        }
        task.resume()
    }
}
