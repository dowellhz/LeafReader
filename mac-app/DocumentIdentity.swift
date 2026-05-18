import CryptoKit
import Foundation

enum DocumentIdentity {
    static func fastID(for url: URL) -> String {
        let cacheKey = legacyCacheKey(for: url)
        let digest = SHA256.hash(data: Data(cacheKey.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "fast-\(digest)"
    }

    static func legacyCacheKey(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)|\(fileSize)|\(modifiedAt)"
    }

    static func selectedID(fastID: String, legacyID: String?, legacyHasData: Bool, fastHasData: Bool) -> String {
        guard let legacyID, legacyID != fastID else {
            return fastID
        }
        if legacyHasData && !fastHasData {
            return legacyID
        }
        return fastID
    }
}
