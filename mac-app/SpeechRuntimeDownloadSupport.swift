import Foundation

extension SpeechRuntimeResourceManager {
    static let downloadErrorDomain = "LeafReader.SpeechRuntime.Download"
    private static let maxDownloadAttempts = 4

    static func shouldRetryDownload(error: NSError, attempt: Int) -> Bool {
        guard attempt < maxDownloadAttempts else { return false }
        if error.domain == downloadErrorDomain, error.code == 416 {
            return true
        }
        if error.domain == NSURLErrorDomain {
            return error.code != NSURLErrorCancelled
        }
        return false
    }

    static func partialDownloadURL(for runtime: Runtime) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/leafreader/downloads", isDirectory: true)
            .appendingPathComponent(runtime.downloadURL.lastPathComponent + ".part")
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
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("下载文件不是有效的模型压缩包，请稍后重试。", "The downloaded file is not a valid model archive. Please try again later.")]
            )
        }
    }
}
