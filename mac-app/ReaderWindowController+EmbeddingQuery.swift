import Cocoa

extension ReaderWindowController {
    func queryEmbedding(for question: String, completion: @escaping ([Float]?) -> Void) {
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion(nil)
            return
        }
        embeddingClient.embed(texts: [question], config: config) { result in
            if case .success(let embeddings) = result {
                completion(embeddings.first)
                return
            }
            completion(nil)
        }
    }
}
