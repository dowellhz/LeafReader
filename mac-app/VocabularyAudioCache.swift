import CryptoKit
import Foundation

enum VocabularyAudioCache {
    static let maximumBytes: Int64 = 100 * 1024 * 1024

    struct Entry {
        let url: URL
        let key: String
    }

    static func entry(text: String, runtimeID: String, voiceID: String, speedID: String) -> Entry {
        let digestInput = "vocabulary-audio-v1|\(runtimeID)|\(voiceID)|\(speedID)|\(text)"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return Entry(url: cacheDirectory.appendingPathComponent("\(digest).wav"), key: digest)
    }

    static func markAccessed(_ url: URL, at date: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    static func store(tempURL: URL, to cacheURL: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: cacheURL)
            try fileManager.moveItem(at: tempURL, to: cacheURL)
            markAccessed(cacheURL)
            pruneIfNeeded()
            return true
        } catch {
            try? fileManager.removeItem(at: tempURL)
            NSLog("LeafReader vocabulary audio cache: store failed output=%@ error=%@", cacheURL.path, error.localizedDescription)
            return false
        }
    }

    static func pruneIfNeeded(maximumBytes: Int64 = maximumBytes) {
        let fileManager = FileManager.default
        let entries = cacheEntries()
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > maximumBytes else { return }
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= maximumBytes {
                break
            }
        }
    }

    static func cacheSizeBytes() -> Int64 {
        cacheEntries().reduce(Int64(0)) { $0 + $1.size }
    }

    private static func cacheEntries() -> [(url: URL, modified: Date, size: Int64)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        ) else {
            return []
        }
        return files.compactMap { url in
            guard url.pathExtension.lowercased() == "wav",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return (
                url: url,
                modified: values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
        }
    }

    private static var cacheDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.linlu.leafreader"
        return root
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("VocabularyAudio", isDirectory: true)
    }
}
