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

    static func sha256HexDigest(for fileURL: URL) throws -> String {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/shasum"),
            arguments: ["-a", "256", fileURL.path],
            timeout: 30
        )
        guard !result.timedOut, result.terminationStatus == 0,
              let output = String(data: result.stdout, encoding: .utf8)?
                .split(separator: " ")
                .first else {
            throw NSError(
                domain: downloadErrorDomain,
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型校验失败，请重试。", "Model verification failed. Please try again.")]
            )
        }
        return String(output)
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
