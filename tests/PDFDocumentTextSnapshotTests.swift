import Foundation

private struct PDFSnapshotTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw PDFSnapshotTestFailure(description: message)
    }
}

@main
struct PDFDocumentTextSnapshotTestRunner {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-pdf-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let documentURL = root.appendingPathComponent("fixture.pdf")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("page-one".utf8).write(to: documentURL)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: documentURL.path)

        var extractionCount = 0
        let extractor: PDFDocumentTextSnapshotCache.PageTextExtractor = { url, token in
            if token.waitUntilRunnableOrCancelled() { throw CancellationError() }
            extractionCount += 1
            return [String(decoding: try Data(contentsOf: url), as: UTF8.self)]
        }

        let first = try PDFDocumentTextSnapshotCache.loadOrCreate(
            url: documentURL,
            cancellationToken: PDFDocumentTextCancellationToken(),
            cacheRoot: cacheRoot,
            pageTextExtractor: extractor
        )
        let second = try PDFDocumentTextSnapshotCache.loadOrCreate(
            url: documentURL,
            cancellationToken: PDFDocumentTextCancellationToken(),
            cacheRoot: cacheRoot,
            pageTextExtractor: extractor
        )
        try require(first == second, "verified cache entry should be reused")
        try require(extractionCount == 1, "cache hit should not extract PDF text again")

        let cacheFiles = try FileManager.default.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        try require(cacheFiles.count == 1, "one content-addressed cache entry should be created")
        try Data("tampered".utf8).write(to: cacheFiles[0])
        let rebuilt = try PDFDocumentTextSnapshotCache.loadOrCreate(
            url: documentURL,
            cancellationToken: PDFDocumentTextCancellationToken(),
            cacheRoot: cacheRoot,
            pageTextExtractor: extractor
        )
        try require(rebuilt.pageTexts == ["page-one"], "tampered cache should be rebuilt")
        try require(extractionCount == 2, "tampered cache should force extraction")

        try Data("page-two".utf8).write(to: documentURL)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: documentURL.path)
        let replaced = try PDFDocumentTextSnapshotCache.loadOrCreate(
            url: documentURL,
            cancellationToken: PDFDocumentTextCancellationToken(),
            cacheRoot: cacheRoot,
            pageTextExtractor: extractor
        )
        try require(replaced.pageTexts == ["page-two"], "content replacement should invalidate cache")
        try require(replaced.contentFingerprint != first.contentFingerprint, "cache identity should include source bytes")

        let cancelledToken = PDFDocumentTextCancellationToken()
        cancelledToken.cancel()
        do {
            _ = try PDFDocumentTextSnapshotCache.loadOrCreate(
                url: documentURL,
                cancellationToken: cancelledToken,
                cacheRoot: cacheRoot,
                pageTextExtractor: extractor
            )
            throw PDFSnapshotTestFailure(description: "cancelled snapshot load should throw")
        } catch is CancellationError {
        }

        print("PDFDocumentTextSnapshotTests passed")
    }
}
