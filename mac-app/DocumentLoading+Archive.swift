import CryptoKit
import Foundation

extension WebDocumentLoader {
    // MARK: - Archive and Text Decoding

    static func unzipEPUBToCache(url: URL) throws -> URL {
        let fileURL = url.standardizedFileURL
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let key = SHA256.hash(data: Data("\(fileURL.path)#\(modified)#\(fileSize)".utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let cacheRoot = try epubCacheRoot()
        cleanupOldEPUBCacheEntries(in: cacheRoot, keeping: key)
        let destination = cacheRoot.appendingPathComponent(key, isDirectory: true)
        let containerURL = destination.appendingPathComponent("META-INF/container.xml")
        if FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            } catch {
                logEPUBCacheFailure("Failed to refresh cache entry modification date at \(destination.path)", error: error)
            }
            return destination
        }

        let temporaryDestination = cacheRoot.appendingPathComponent("\(key)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDestination, withIntermediateDirectories: true)
        do {
            try unzip(url: fileURL, to: temporaryDestination)
            if FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.removeItem(at: destination)
                } catch {
                    logEPUBCacheFailure("Failed to replace existing cache entry at \(destination.path)", error: error)
                }
            }
            try FileManager.default.moveItem(at: temporaryDestination, to: destination)
            return destination
        } catch {
            do {
                try FileManager.default.removeItem(at: temporaryDestination)
            } catch {
                logEPUBCacheFailure("Failed to remove temporary cache entry at \(temporaryDestination.path)", error: error)
            }
            throw error
        }
    }

    static func epubCacheRoot() throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cacheRoot = root
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("EPUBCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        return cacheRoot
    }

    static func cleanupOldEPUBCacheEntries(in cacheRoot: URL, keeping currentKey: String) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: cacheRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logEPUBCacheFailure("Failed to list EPUB cache directory at \(cacheRoot.path)", error: error)
            return
        }
        guard entries.count > 10 else {
            return
        }
        let staleEntries = entries
            .filter { $0.lastPathComponent != currentKey }
            .sorted {
                let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
            .prefix(max(0, entries.count - 10))
        for entry in staleEntries {
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                logEPUBCacheFailure("Failed to remove stale cache entry at \(entry.path)", error: error)
            }
        }
    }

    static func logEPUBCacheFailure(_ message: String, error: Error) {
        NSLog("LeafReader EPUB cache: %@ (error=%@)", message, error.localizedDescription)
    }

    static func unzip(url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try unzip(url: url, to: destination)
        return destination
    }

    static func unzip(url: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LeafReader", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Unable to unpack \(url.lastPathComponent)"
            ])
        }
    }

    static func zipEntryData(in url: URL, entryPath: String) throws -> Data? {
        guard let entryPath = EPUBPathResolver.safeArchivePath(entryPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entryPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

}
