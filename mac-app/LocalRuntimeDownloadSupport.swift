import CryptoKit
import Foundation

enum LocalRuntimeDownloadSupport {
    static let downloadErrorDomain = "LeafReader.LocalRuntime.Download"
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

    static func expectedDownloadTotalBytes(asset: LocalRuntimeDownloadManifestAsset?) -> Int64? {
        guard let size = asset?.byteSize, size > 0 else { return nil }
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
        for plan: LocalRuntimeDownloadPlan,
        archiveURL: URL,
        asset: LocalRuntimeDownloadManifestAsset?
    ) throws {
        let archiveSize = asset?.byteSize ?? partialDownloadSize(at: archiveURL)
        let requiredBytes = requiredInstallFreeSpaceBytes(archiveSize: archiveSize)
        let availableBytes = availableDiskSpaceBytes(for: plan.descriptor.installDirectory.deletingLastPathComponent())
        guard hasEnoughFreeSpace(availableBytes: availableBytes, requiredBytes: requiredBytes) else {
            throw NSError(
                domain: downloadErrorDomain,
                code: insufficientDiskSpaceCode,
                userInfo: [
                    NSLocalizedDescriptionKey: AppText.localized(
                        "磁盘空间不足，无法安装本地运行时。请清理空间后重试。",
                        "Not enough disk space to install the local runtime. Free up space and try again."
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
            || error.code == -9
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

    static func partialDownloadURL(for plan: LocalRuntimeDownloadPlan) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader/downloads", isDirectory: true)
            .appendingPathComponent(plan.archiveURL.lastPathComponent + ".part")
    }

    static func partialDownloadMetadataURL(for plan: LocalRuntimeDownloadPlan) -> URL {
        partialDownloadURL(for: plan).appendingPathExtension("meta")
    }

    static func partialDownloadMetadataMatches(
        _ metadata: PartialDownloadMetadata,
        plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?
    ) -> Bool {
        metadata.downloadURL == plan.archiveURL.absoluteString
            && metadata.assetName == asset?.assetName
            && metadata.expectedSize == asset?.byteSize
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

    static func readPartialDownloadMetadata(for plan: LocalRuntimeDownloadPlan) -> PartialDownloadMetadata? {
        guard let data = try? Data(contentsOf: partialDownloadMetadataURL(for: plan)) else {
            return nil
        }
        return try? JSONDecoder().decode(PartialDownloadMetadata.self, from: data)
    }

    static func writePartialDownloadMetadata(
        for plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?,
        response: URLResponse
    ) {
        let httpResponse = response as? HTTPURLResponse
        let metadata = PartialDownloadMetadata(
            downloadURL: plan.archiveURL.absoluteString,
            assetName: asset?.assetName,
            expectedSize: asset?.byteSize,
            sha256: asset?.sha256,
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified")
        )
        do {
            let metadataURL = partialDownloadMetadataURL(for: plan)
            try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
        } catch {
            NSLog("LeafReader local runtime download: failed to write partial metadata (%@)", String(describing: error))
        }
    }

    static func removePartialDownload(for plan: LocalRuntimeDownloadPlan) {
        try? FileManager.default.removeItem(at: partialDownloadURL(for: plan))
        try? FileManager.default.removeItem(at: partialDownloadMetadataURL(for: plan))
    }

    static func resumablePartialDownloadSize(
        for plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?
    ) -> Int64 {
        let size = partialDownloadSize(at: partialDownloadURL(for: plan))
        guard size > 0,
              let metadata = readPartialDownloadMetadata(for: plan),
              partialDownloadMetadataMatches(metadata, plan: plan, asset: asset) else {
            removePartialDownload(for: plan)
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

    static func validateArchive(at archiveURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 2)
        guard magic == Data([0x1f, 0x8b]) else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("下载文件不是有效的运行时压缩包，请稍后重试。", "The downloaded file is not a valid runtime archive. Please try again later.")]
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

    static func validateArchiveManifest(_ archiveURL: URL, asset: LocalRuntimeDownloadManifestAsset?) throws {
        guard let asset,
              let expectedSize = asset.byteSize,
              expectedSize > 0,
              asset.sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("缺少可信的模型校验信息，已停止安装。", "Trusted runtime verification metadata is missing; installation was stopped.")]
            )
        }
        let actualSize = partialDownloadSize(at: archiveURL)
        guard actualSize == expectedSize else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("运行时文件大小校验失败，请重新下载。", "Runtime file size verification failed. Please download it again.")]
            )
        }
        try validateArchiveChecksum(archiveURL, expectedSHA256: asset.sha256)
    }

    static func validateArchiveChecksum(_ archiveURL: URL, expectedSHA256: String?) throws {
        guard let expectedSHA256,
              expectedSHA256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("缺少可信的 SHA-256 校验值。", "A trusted SHA-256 checksum is required.")]
            )
        }
        let actual = try sha256HexDigest(for: archiveURL)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("运行时文件校验失败，请重新下载。", "Runtime checksum verification failed. Please download it again.")]
            )
        }
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
}
