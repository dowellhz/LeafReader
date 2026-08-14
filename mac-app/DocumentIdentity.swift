import CryptoKit
import Foundation

enum DocumentIdentity {
    private static let contentMappingDefaultsKey = "documentIdentity.contentMappings.v1"
    private static let legacyOwnerDefaultsKey = "documentIdentity.legacyOwners.v1"
    private static let readChunkSize = 1_048_576

    static func contentIdentifiers(
        for url: URL,
        isCancelled: () -> Bool = { false }
    ) throws -> (contentID: String, legacyMD5: String) {
        let handle = try FileHandle(forReadingFrom: url.standardizedFileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        var legacyHasher = Insecure.MD5()
        while true {
            if isCancelled() { throw CancellationError() }
            let data = handle.readData(ofLength: readChunkSize)
            if data.isEmpty { break }
            hasher.update(data: data)
            legacyHasher.update(data: data)
        }
        if isCancelled() { throw CancellationError() }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let legacyDigest = legacyHasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ("content-v1-\(digest)", legacyDigest)
    }

    static func contentID(for url: URL, isCancelled: () -> Bool = { false }) throws -> String {
        try contentIdentifiers(for: url, isCancelled: isCancelled).contentID
    }

    static func storageID(
        contentID: String,
        metadataID: String?,
        legacyID: String?,
        defaults: UserDefaults = .standard,
        hasStoredData: (String) -> Bool
    ) -> String {
        var mappings = defaults.dictionary(forKey: contentMappingDefaultsKey) as? [String: String] ?? [:]
        if let mappedID = mappings[contentID], !mappedID.isEmpty {
            return mappedID
        }
        if hasStoredData(contentID) {
            mappings[contentID] = contentID
            defaults.set(mappings, forKey: contentMappingDefaultsKey)
            return contentID
        }

        var legacyOwners = defaults.dictionary(forKey: legacyOwnerDefaultsKey) as? [String: String] ?? [:]
        let candidates = [metadataID, legacyID].compactMap { $0 }.filter { !$0.isEmpty }
        for candidate in candidates where hasStoredData(candidate) {
            guard legacyOwners[candidate] == nil || legacyOwners[candidate] == contentID else {
                continue
            }
            legacyOwners[candidate] = contentID
            mappings[contentID] = candidate
            defaults.set(legacyOwners, forKey: legacyOwnerDefaultsKey)
            defaults.set(mappings, forKey: contentMappingDefaultsKey)
            return candidate
        }

        mappings[contentID] = contentID
        defaults.set(mappings, forKey: contentMappingDefaultsKey)
        return contentID
    }

    static func migrationMetadataID(
        fastID: String,
        cachedLegacyID: String?,
        computedLegacyID: String
    ) -> String? {
        guard let cachedLegacyID else { return fastID }
        return cachedLegacyID == computedLegacyID ? fastID : nil
    }

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
