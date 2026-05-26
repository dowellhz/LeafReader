import CryptoKit
import Foundation

extension SpeechRuntimeResourceManager {
    static let downloadErrorDomain = "LeafReader.SpeechRuntime.Download"
    static let resumeRangeMismatchCode = 417
    static let insufficientDiskSpaceCode = -10
    private static let maxDownloadAttempts = 4
    private static let minimumInstallSafetyMarginBytes: Int64 = 200 * 1024 * 1024

    enum DownloadRecoveryAction: Equatable {
        case retry(resumePartial: Bool)
        case fail(removePartial: Bool)
    }

    struct PartialDownloadMetadata: Codable, Equatable {
        let downloadURL: String
        let assetName: String?
        let expectedSize: Int64?
        let sha256: String?
        let eTag: String?
        let lastModified: String?
    }

    static func shouldRetryDownload(error: NSError, attempt: Int) -> Bool {
        guard attempt < maxDownloadAttempts else { return false }
        if error.domain == downloadErrorDomain,
           shouldRestartWithoutPartialDownload(error: error) {
            return true
        }
        if error.domain == NSURLErrorDomain {
            return error.code != NSURLErrorCancelled
        }
        return false
    }

    static func downloadRecoveryAction(error: NSError, attempt: Int) -> DownloadRecoveryAction {
        let removePartial = shouldRestartWithoutPartialDownload(error: error)
        if shouldRetryDownload(error: error, attempt: attempt) {
            return .retry(resumePartial: !removePartial)
        }
        return .fail(removePartial: removePartial)
    }

    static func downloadSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func expectedDownloadTotalBytes(asset: SpeechModelManifest.Asset?) -> Int64? {
        guard let size = asset?.size, size > 0 else { return nil }
        return size
    }

    static func requiredInstallFreeSpaceBytes(archiveSize: Int64) -> Int64 {
        max(0, archiveSize) * 3 + minimumInstallSafetyMarginBytes
    }

    static func hasEnoughFreeSpace(availableBytes: Int64?, requiredBytes: Int64) -> Bool {
        guard let availableBytes else { return true }
        return availableBytes >= requiredBytes
    }

    static func validateAvailableDiskSpace(
        for runtime: Runtime,
        archiveURL: URL,
        asset: SpeechModelManifest.Asset?
    ) throws {
        let archiveSize = asset?.size ?? partialDownloadSize(at: archiveURL)
        let requiredBytes = requiredInstallFreeSpaceBytes(archiveSize: archiveSize)
        let availableBytes = availableDiskSpaceBytes(for: runtime.installDirectory.deletingLastPathComponent())
        guard hasEnoughFreeSpace(availableBytes: availableBytes, requiredBytes: requiredBytes) else {
            throw NSError(
                domain: downloadErrorDomain,
                code: insufficientDiskSpaceCode,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "磁盘空间不足，无法安装朗读模型。请清理空间后重试。",
                        "Not enough disk space to install the speech model. Free up space and try again."
                    )
                ]
            )
        }
    }

    static func shouldRestartWithoutPartialDownload(error: NSError) -> Bool {
        guard error.domain == downloadErrorDomain else { return false }
        return error.code == 416
            || error.code == resumeRangeMismatchCode
            || error.code == -3
            || error.code == -7
            || error.code == -8
    }

    static func contentRangeStart(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let pattern = #"(?i)^\s*bytes\s+(\d+)-\d+/(\d+|\*)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Int64(value[range])
    }

    static func partialDownloadURL(for runtime: Runtime) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader/downloads", isDirectory: true)
            .appendingPathComponent(runtime.downloadURL.lastPathComponent + ".part")
    }

    static func partialDownloadMetadataURL(for runtime: Runtime) -> URL {
        partialDownloadURL(for: runtime).appendingPathExtension("meta")
    }

    static func partialDownloadMetadataMatches(
        _ metadata: PartialDownloadMetadata,
        runtime: Runtime,
        asset: SpeechModelManifest.Asset?
    ) -> Bool {
        metadata.downloadURL == runtime.downloadURL.absoluteString
            && metadata.assetName == asset?.name
            && metadata.expectedSize == asset?.size
            && metadata.sha256 == asset?.sha256
    }

    static func ifRangeHeaderValue(for metadata: PartialDownloadMetadata) -> String? {
        if let eTag = metadata.eTag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eTag.isEmpty {
            return eTag
        }
        if let lastModified = metadata.lastModified?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastModified.isEmpty {
            return lastModified
        }
        return nil
    }

    static func readPartialDownloadMetadata(for runtime: Runtime) -> PartialDownloadMetadata? {
        guard let data = try? Data(contentsOf: partialDownloadMetadataURL(for: runtime)) else {
            return nil
        }
        return try? JSONDecoder().decode(PartialDownloadMetadata.self, from: data)
    }

    static func writePartialDownloadMetadata(
        for runtime: Runtime,
        asset: SpeechModelManifest.Asset?,
        response: URLResponse
    ) {
        let httpResponse = response as? HTTPURLResponse
        let metadata = PartialDownloadMetadata(
            downloadURL: runtime.downloadURL.absoluteString,
            assetName: asset?.name,
            expectedSize: asset?.size,
            sha256: asset?.sha256,
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified")
        )
        do {
            let metadataURL = partialDownloadMetadataURL(for: runtime)
            try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
        } catch {
            NSLog("LeafReader speech download: failed to write partial metadata (%@)", String(describing: error))
        }
    }

    static func removePartialDownload(for runtime: Runtime) {
        try? FileManager.default.removeItem(at: partialDownloadURL(for: runtime))
        try? FileManager.default.removeItem(at: partialDownloadMetadataURL(for: runtime))
    }

    static func resumablePartialDownloadSize(for runtime: Runtime, asset: SpeechModelManifest.Asset?) -> Int64 {
        let size = partialDownloadSize(at: partialDownloadURL(for: runtime))
        guard size > 0,
              let metadata = readPartialDownloadMetadata(for: runtime),
              partialDownloadMetadataMatches(metadata, runtime: runtime, asset: asset) else {
            removePartialDownload(for: runtime)
            return 0
        }
        return size
    }

    static func partialDownloadSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func availableDiskSpaceBytes(for directory: URL) -> Int64? {
        let existingDirectory = existingAncestorDirectory(for: directory)
        if let values = try? existingDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: existingDirectory.path),
           let freeSize = attributes[.systemFreeSize] as? NSNumber {
            return freeSize.int64Value
        }
        return nil
    }

    private static func existingAncestorDirectory(for url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return candidate
    }

    static func validateArchive(at archiveURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 2)
        guard magic == Data([0x1f, 0x8b]) else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("下载文件不是有效的模型压缩包，请稍后重试。", "The downloaded file is not a valid model archive. Please try again later.")]
            )
        }
    }

    static func sha256HexDigest(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func validateArchiveManifest(_ archiveURL: URL, asset: SpeechModelManifest.Asset?) throws {
        guard let asset else { return }
        if let expectedSize = asset.size {
            let actualSize = partialDownloadSize(at: archiveURL)
            guard actualSize == expectedSize else {
                throw NSError(
                    domain: downloadErrorDomain,
                    code: -8,
                    userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型文件大小校验失败，请重新下载。", "Model file size verification failed. Please download it again.")]
                )
            }
        }
        try validateArchiveChecksum(archiveURL, expectedSHA256: asset.sha256)
    }

    static func validateArchiveChecksum(_ archiveURL: URL, expectedSHA256: String?) throws {
        guard let expectedSHA256,
              !expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let actual = try sha256HexDigest(for: archiveURL)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型文件校验失败，请重新下载。", "Model checksum verification failed. Please download it again.")]
            )
        }
    }
}
