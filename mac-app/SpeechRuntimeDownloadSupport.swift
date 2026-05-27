import Foundation

extension SpeechRuntimeResourceManager {
    typealias DownloadRecoveryAction = LocalRuntimeDownloadSupport.DownloadRecoveryAction
    typealias PartialDownloadMetadata = LocalRuntimeDownloadSupport.PartialDownloadMetadata

    static let downloadErrorDomain = LocalRuntimeDownloadSupport.downloadErrorDomain
    static let resumeRangeMismatchCode = LocalRuntimeDownloadSupport.resumeRangeMismatchCode
    static let insufficientDiskSpaceCode = LocalRuntimeDownloadSupport.insufficientDiskSpaceCode

    static func shouldRetryDownload(error: NSError, attempt: Int) -> Bool {
        LocalRuntimeDownloadSupport.shouldRetryDownload(error: error, attempt: attempt)
    }

    static func downloadRecoveryAction(error: NSError, attempt: Int) -> DownloadRecoveryAction {
        LocalRuntimeDownloadSupport.downloadRecoveryAction(error: error, attempt: attempt)
    }

    static func downloadSessionConfiguration() -> URLSessionConfiguration {
        LocalRuntimeDownloadSupport.downloadSessionConfiguration()
    }

    static func expectedDownloadTotalBytes(asset: LocalRuntimeDownloadManifestAsset?) -> Int64? {
        LocalRuntimeDownloadSupport.expectedDownloadTotalBytes(asset: asset)
    }

    static func requiredInstallFreeSpaceBytes(archiveSize: Int64) -> Int64 {
        LocalRuntimeDownloadSupport.requiredInstallFreeSpaceBytes(archiveSize: archiveSize)
    }

    static func hasEnoughFreeSpace(availableBytes: Int64?, requiredBytes: Int64) -> Bool {
        LocalRuntimeDownloadSupport.hasEnoughFreeSpace(availableBytes: availableBytes, requiredBytes: requiredBytes)
    }

    static func validateAvailableDiskSpace(
        for runtime: Runtime,
        archiveURL: URL,
        asset: LocalRuntimeDownloadManifestAsset?
    ) throws {
        try LocalRuntimeDownloadSupport.validateAvailableDiskSpace(
            for: runtime.localRuntimeDownloadPlan,
            archiveURL: archiveURL,
            asset: asset
        )
    }

    static func validateAvailableDiskSpace(
        for plan: LocalRuntimeDownloadPlan,
        archiveURL: URL,
        asset: LocalRuntimeDownloadManifestAsset?
    ) throws {
        try LocalRuntimeDownloadSupport.validateAvailableDiskSpace(
            for: plan,
            archiveURL: archiveURL,
            asset: asset
        )
    }

    static func shouldRestartWithoutPartialDownload(error: NSError) -> Bool {
        LocalRuntimeDownloadSupport.shouldRestartWithoutPartialDownload(error: error)
    }

    static func contentRangeStart(_ value: String?) -> Int64? {
        LocalRuntimeDownloadSupport.contentRangeStart(value)
    }

    static func partialDownloadURL(for runtime: Runtime) -> URL {
        LocalRuntimeDownloadSupport.partialDownloadURL(for: runtime.localRuntimeDownloadPlan)
    }

    static func partialDownloadURL(for plan: LocalRuntimeDownloadPlan) -> URL {
        LocalRuntimeDownloadSupport.partialDownloadURL(for: plan)
    }

    static func partialDownloadMetadataURL(for runtime: Runtime) -> URL {
        LocalRuntimeDownloadSupport.partialDownloadMetadataURL(for: runtime.localRuntimeDownloadPlan)
    }

    static func partialDownloadMetadataURL(for plan: LocalRuntimeDownloadPlan) -> URL {
        LocalRuntimeDownloadSupport.partialDownloadMetadataURL(for: plan)
    }

    static func partialDownloadMetadataMatches(
        _ metadata: PartialDownloadMetadata,
        runtime: Runtime,
        asset: LocalRuntimeDownloadManifestAsset?
    ) -> Bool {
        LocalRuntimeDownloadSupport.partialDownloadMetadataMatches(
            metadata,
            plan: runtime.localRuntimeDownloadPlan,
            asset: asset
        )
    }

    static func partialDownloadMetadataMatches(
        _ metadata: PartialDownloadMetadata,
        plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?
    ) -> Bool {
        LocalRuntimeDownloadSupport.partialDownloadMetadataMatches(metadata, plan: plan, asset: asset)
    }

    static func ifRangeHeaderValue(for metadata: PartialDownloadMetadata) -> String? {
        LocalRuntimeDownloadSupport.ifRangeHeaderValue(for: metadata)
    }

    static func readPartialDownloadMetadata(for runtime: Runtime) -> PartialDownloadMetadata? {
        LocalRuntimeDownloadSupport.readPartialDownloadMetadata(for: runtime.localRuntimeDownloadPlan)
    }

    static func readPartialDownloadMetadata(for plan: LocalRuntimeDownloadPlan) -> PartialDownloadMetadata? {
        LocalRuntimeDownloadSupport.readPartialDownloadMetadata(for: plan)
    }

    static func writePartialDownloadMetadata(
        for runtime: Runtime,
        asset: LocalRuntimeDownloadManifestAsset?,
        response: URLResponse
    ) {
        LocalRuntimeDownloadSupport.writePartialDownloadMetadata(
            for: runtime.localRuntimeDownloadPlan,
            asset: asset,
            response: response
        )
    }

    static func writePartialDownloadMetadata(
        for plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?,
        response: URLResponse
    ) {
        LocalRuntimeDownloadSupport.writePartialDownloadMetadata(for: plan, asset: asset, response: response)
    }

    static func removePartialDownload(for runtime: Runtime) {
        LocalRuntimeDownloadSupport.removePartialDownload(for: runtime.localRuntimeDownloadPlan)
    }

    static func removePartialDownload(for plan: LocalRuntimeDownloadPlan) {
        LocalRuntimeDownloadSupport.removePartialDownload(for: plan)
    }

    static func resumablePartialDownloadSize(for runtime: Runtime, asset: LocalRuntimeDownloadManifestAsset?) -> Int64 {
        LocalRuntimeDownloadSupport.resumablePartialDownloadSize(for: runtime.localRuntimeDownloadPlan, asset: asset)
    }

    static func resumablePartialDownloadSize(
        for plan: LocalRuntimeDownloadPlan,
        asset: LocalRuntimeDownloadManifestAsset?
    ) -> Int64 {
        LocalRuntimeDownloadSupport.resumablePartialDownloadSize(for: plan, asset: asset)
    }

    static func partialDownloadSize(at url: URL) -> Int64 {
        LocalRuntimeDownloadSupport.partialDownloadSize(at: url)
    }

    static func validateArchive(at archiveURL: URL) throws {
        try LocalRuntimeDownloadSupport.validateArchive(at: archiveURL)
    }

    static func sha256HexDigest(for fileURL: URL) throws -> String {
        try LocalRuntimeDownloadSupport.sha256HexDigest(for: fileURL)
    }

    static func validateArchiveManifest(_ archiveURL: URL, asset: LocalRuntimeDownloadManifestAsset?) throws {
        try LocalRuntimeDownloadSupport.validateArchiveManifest(archiveURL, asset: asset)
    }

    static func validateArchiveChecksum(_ archiveURL: URL, expectedSHA256: String?) throws {
        try LocalRuntimeDownloadSupport.validateArchiveChecksum(archiveURL, expectedSHA256: expectedSHA256)
    }
}
