import Foundation

struct KokoroWorkerResponse: Codable, Equatable {
    let id: String
    let ok: Bool
    let error: String?
}

struct KokoroWorkerResponseReader {
    private let requestID: String
    private let decoder = JSONDecoder()
    private var buffer = Data()

    init(requestID: String) {
        self.requestID = requestID
    }

    mutating func append(_ data: Data) -> KokoroWorkerResponse? {
        guard !data.isEmpty else { return nil }
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard let response = try? decoder.decode(KokoroWorkerResponse.self, from: Data(lineData)),
                  response.id == requestID else {
                continue
            }
            return response
        }
        return nil
    }
}
