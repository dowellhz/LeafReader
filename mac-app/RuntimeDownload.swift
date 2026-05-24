import Foundation

final class RuntimeDownload: NSObject, URLSessionDataDelegate {
    private static let errorDomain = "LeafReader.SpeechRuntime.Download"

    private let runtime: SpeechRuntimeResourceManager.Runtime
    private let downloadID: UUID
    private let partialURL: URL
    private let existingSize: Int64
    private let retryingWithoutResume: Bool
    private let expectedAsset: SpeechModelManifest.Asset?
    private let expectedTotalBytes: Int64?
    private let completion: (Result<Void, Error>) -> Void
    private var fileHandle: FileHandle?
    private var expectedBytes: Int64?
    private var completedBytes: Int64
    private var completionSent = false
    private var downloadError: Error?

    var session: URLSession?
    weak var task: URLSessionTask?

    init(
        runtime: SpeechRuntimeResourceManager.Runtime,
        downloadID: UUID,
        partialURL: URL,
        existingSize: Int64,
        retryingWithoutResume: Bool,
        expectedAsset: SpeechModelManifest.Asset?,
        expectedTotalBytes: Int64?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.runtime = runtime
        self.downloadID = downloadID
        self.partialURL = partialURL
        self.existingSize = existingSize
        self.retryingWithoutResume = retryingWithoutResume
        self.expectedAsset = expectedAsset
        self.expectedTotalBytes = expectedTotalBytes
        self.completion = completion
        self.completedBytes = existingSize
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            try prepareDestination(for: response)
            completionHandler(.allow)
        } catch {
            downloadError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            completedBytes += Int64(data.count)
            SpeechRuntimeResourceManager.updateDownloadProgress(
                runtime,
                downloadID: downloadID,
                completedBytes: completedBytes,
                expectedBytes: expectedBytes
            )
        } catch {
            downloadError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil
        session.invalidateAndCancel()

        guard !completionSent else { return }
        completionSent = true

        if let downloadError {
            completion(.failure(downloadError))
        } else if let error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    private func prepareDestination(for response: URLResponse) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        if existingSize > 0, statusCode == 416, !retryingWithoutResume {
            throw makeError(
                code: 416,
                message: AppText.localized(
                    "续传位置已失效，正在重新下载。",
                    "Resume position expired; restarting download."
                )
            )
        }

        guard (200...299).contains(statusCode) else {
            throw makeError(
                code: statusCode,
                message: AppText.localized(
                    "模型下载失败：服务器返回 HTTP \(statusCode)。",
                    "Model download failed: server returned HTTP \(statusCode)."
                )
            )
        }

        if existingSize > 0, statusCode == 206 {
            let contentRange = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")
            guard SpeechRuntimeResourceManager.contentRangeStart(contentRange) == existingSize else {
                throw makeError(
                    code: SpeechRuntimeResourceManager.resumeRangeMismatchCode,
                    message: AppText.localized(
                        "续传响应不匹配，正在重新下载。",
                        "Resume response did not match the partial file; restarting download."
                    )
                )
            }
            SpeechRuntimeResourceManager.writePartialDownloadMetadata(
                for: runtime,
                asset: expectedAsset,
                response: response
            )
            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle?.seekToEnd()
            completedBytes = existingSize
            expectedBytes = expectedDownloadBytes(from: response, existingSize: existingSize)
            return
        }

        try? fileManager.removeItem(at: partialURL)
        fileManager.createFile(atPath: partialURL.path, contents: nil)
        SpeechRuntimeResourceManager.writePartialDownloadMetadata(
            for: runtime,
            asset: expectedAsset,
            response: response
        )
        fileHandle = try FileHandle(forWritingTo: partialURL)
        completedBytes = 0
        expectedBytes = expectedDownloadBytes(from: response, existingSize: 0)
    }

    private func expectedDownloadBytes(from response: URLResponse, existingSize: Int64) -> Int64? {
        if let expectedTotalBytes, expectedTotalBytes > 0 {
            return expectedTotalBytes
        }
        let length = response.expectedContentLength
        return length > 0 ? existingSize + length : nil
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: Self.errorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
