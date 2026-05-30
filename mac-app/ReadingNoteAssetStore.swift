import Foundation

enum ReadingNoteAssetStore {
    static func defaultDirectoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("ReadingNoteAssets", isDirectory: true)
    }

    static func importImage(from sourceURL: URL, directoryURL: URL? = defaultDirectoryURL()) throws -> URL {
        guard let directoryURL else {
            throw NSError(domain: "LeafReader.ReadingNoteAssetStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Reading note asset directory is unavailable"
            ])
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destinationURL = uniqueDestinationURL(for: sourceURL, in: directoryURL)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let fileExtension = sourceURL.pathExtension
        let baseName = sanitizedBaseName(sourceURL.deletingPathExtension().lastPathComponent)
        let fileName = fileExtension.isEmpty
            ? "\(baseName)-\(UUID().uuidString)"
            : "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        return directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func sanitizedBaseName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "image" : sanitized
    }
}
