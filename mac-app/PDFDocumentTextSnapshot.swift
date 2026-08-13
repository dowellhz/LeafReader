import CryptoKit
import Foundation
import PDFKit

struct PDFDocumentTextSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let contentFingerprint: String
    let pageTexts: [String]

    func pageText(at index: Int) -> String? {
        guard pageTexts.indices.contains(index) else { return nil }
        return pageTexts[index]
    }
}

final class PDFDocumentTextCancellationToken {
    private let lock = NSLock()
    private var isCancellationRequested = false
    private var deferredUntil: TimeInterval = 0

    func cancel() {
        lock.lock()
        isCancellationRequested = true
        lock.unlock()
    }

    func deferWork(for duration: TimeInterval) {
        guard duration > 0 else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + duration
        lock.lock()
        deferredUntil = max(deferredUntil, deadline)
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancellationRequested
    }

    func waitUntilRunnableOrCancelled() -> Bool {
        while true {
            lock.lock()
            let isCancelled = isCancellationRequested
            let remainingDelay = deferredUntil - ProcessInfo.processInfo.systemUptime
            lock.unlock()
            if isCancelled { return true }
            guard remainingDelay > 0 else { return false }
            Thread.sleep(forTimeInterval: min(0.05, remainingDelay))
        }
    }
}

enum PDFDocumentTextSnapshotCache {
    typealias PageTextExtractor = (URL, PDFDocumentTextCancellationToken) throws -> [String]

    private struct CacheEnvelope: Codable {
        let snapshot: PDFDocumentTextSnapshot
        let pageTextsChecksum: String
    }

    private static let maximumEntryCount = 12

    static func loadOrCreate(
        url: URL,
        cancellationToken: PDFDocumentTextCancellationToken
    ) throws -> PDFDocumentTextSnapshot {
        try loadOrCreate(
            url: url,
            cancellationToken: cancellationToken,
            cacheRoot: nil,
            pageTextExtractor: extractPageTexts
        )
    }

    static func loadOrCreate(
        url: URL,
        cancellationToken: PDFDocumentTextCancellationToken,
        cacheRoot: URL?,
        pageTextExtractor: PageTextExtractor
    ) throws -> PDFDocumentTextSnapshot {
        let fingerprint = try contentFingerprint(for: url, cancellationToken: cancellationToken)
        try throwIfCancelled(cancellationToken)
        let cacheURL = try cacheFileURL(fingerprint: fingerprint, cacheRoot: cacheRoot)
        if let cached = loadVerified(cacheURL: cacheURL, fingerprint: fingerprint) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
            return cached
        }

        let pageTexts = try pageTextExtractor(url, cancellationToken)
        try throwIfCancelled(cancellationToken)
        let extractedFingerprint = try contentFingerprint(for: url, cancellationToken: cancellationToken)
        guard extractedFingerprint == fingerprint else {
            throw CocoaError(.fileReadUnknown)
        }
        let snapshot = PDFDocumentTextSnapshot(
            schemaVersion: PDFDocumentTextSnapshot.currentSchemaVersion,
            contentFingerprint: fingerprint,
            pageTexts: pageTexts
        )
        let envelope = CacheEnvelope(
            snapshot: snapshot,
            pageTextsChecksum: checksum(for: pageTexts)
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: cacheURL, options: .atomic)
        pruneCache(excluding: cacheURL)
        return snapshot
    }

    private static func extractPageTexts(
        url: URL,
        cancellationToken: PDFDocumentTextCancellationToken
    ) throws -> [String] {
        guard let document = PDFDocument(url: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)
        for pageIndex in 0..<document.pageCount {
            try throwIfCancelled(cancellationToken)
            pageTexts.append(document.page(at: pageIndex)?.string ?? "")
        }
        return pageTexts
    }

    private static func contentFingerprint(
        for url: URL,
        cancellationToken: PDFDocumentTextCancellationToken
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url.standardizedFileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try throwIfCancelled(cancellationToken)
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func throwIfCancelled(_ token: PDFDocumentTextCancellationToken) throws {
        if token.waitUntilRunnableOrCancelled() {
            throw CancellationError()
        }
    }

    private static func loadVerified(cacheURL: URL, fingerprint: String) -> PDFDocumentTextSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.snapshot.schemaVersion == PDFDocumentTextSnapshot.currentSchemaVersion,
              envelope.snapshot.contentFingerprint == fingerprint,
              envelope.pageTextsChecksum == checksum(for: envelope.snapshot.pageTexts) else {
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }
        return envelope.snapshot
    }

    private static func cacheFileURL(fingerprint: String, cacheRoot: URL?) throws -> URL {
        let root: URL
        if let cacheRoot {
            root = cacheRoot
        } else if let override = ProcessInfo.processInfo.environment["LEAFREADER_PDF_TEXT_CACHE_ROOT"],
           !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            root = caches
                .appendingPathComponent("LeafReader", isDirectory: true)
                .appendingPathComponent("PDFTextSnapshots", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(fingerprint).json")
    }

    private static func checksum(for pageTexts: [String]) -> String {
        let data = (try? JSONEncoder().encode(pageTexts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func pruneCache(excluding currentURL: URL) {
        let root = currentURL.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let entries = urls.compactMap { url -> (URL, Date)? in
            guard url != currentURL,
                  url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for entry in entries.dropFirst(maximumEntryCount - 1) {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }
}
