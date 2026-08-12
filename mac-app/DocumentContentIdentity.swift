import CryptoKit
import Foundation

enum DocumentContentIdentity {
    static func sha256Key(for url: URL, prefixBytes: Int = 32) throws -> String {
        let handle = try FileHandle(forReadingFrom: url.standardizedFileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
            .prefix(max(1, min(prefixBytes, SHA256.byteCount)))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
