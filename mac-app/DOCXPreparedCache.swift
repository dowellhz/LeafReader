import CryptoKit
import Foundation

struct DOCXPreparedCachePolicy {
    let maximumBytes: Int64
    let maximumEntries: Int

    init(maximumBytes: Int64 = 512 * 1_024 * 1_024, maximumEntries: Int = 10) {
        self.maximumBytes = maximumBytes
        self.maximumEntries = maximumEntries
    }
}

private struct DOCXPreparedTOCItem: Codable {
    let title: String
    let href: String
    let level: Int

    init(_ item: ReaderTOCItem) {
        title = item.title
        href = item.href
        level = item.level
    }

    var readerItem: ReaderTOCItem {
        ReaderTOCItem(title: title, href: href, level: level)
    }
}

private struct DOCXPreparedMediaFile: Codable {
    let path: String
    let bytes: Int64
}

private struct DOCXPreparedManifest: Codable {
    let schemaVersion: Int
    let fingerprint: String
    let title: String
    let entryBytes: Int64
    let htmlSHA256: String
    let plainTextSHA256: String
    let tocSHA256: String
    let media: [DOCXPreparedMediaFile]
}

enum DOCXPreparedCache {
    static let schemaVersion = 2
    static let manifestName = "manifest.json"
    static let htmlName = "rendered.html"
    static let plainTextName = "plain-text.txt"
    static let tocName = "toc.json"

    static func root(override: URL? = nil) throws -> URL {
        let root: URL
        if let override {
            root = override
        } else if let path = ProcessInfo.processInfo.environment["LEAFREADER_DOCX_CACHE_ROOT"],
                  !path.isEmpty {
            root = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            root = caches
                .appendingPathComponent("LeafReader", isDirectory: true)
                .appendingPathComponent("DOCXPreparedCache", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func key(fingerprint: String, title: String) -> String {
        digest(Data("\(schemaVersion)\u{0}\(fingerprint)\u{0}\(title)".utf8))
    }

    static func selectedArchiveEntries(from entries: [String]) throws -> [String] {
        for path in entries {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.contains("\\"),
                  !path.contains("\0"),
                  !path.hasPrefix("/"),
                  !components.contains(".."),
                  EPUBPathResolver.safeArchivePath(path) != nil else {
                throw cacheError(AppText.localized(
                    "DOCX 压缩包包含不安全路径。",
                    "The DOCX archive contains an unsafe path: \(path)"
                ), code: -3)
            }
        }
        guard entries.contains("word/document.xml") else {
            throw cacheError(AppText.localized(
                "DOCX 中缺少 word/document.xml。",
                "The DOCX archive has no word/document.xml entry."
            ), code: -2)
        }
        return entries.filter {
            $0 == "word/document.xml"
                || $0 == "word/_rels/document.xml.rels"
                || ($0.hasPrefix("word/media/") && !$0.hasSuffix("/"))
        }
    }

    static func load(
        directory: URL,
        fingerprint: String,
        title: String,
        ownedResource: OwnedTemporaryResource? = nil,
        measurements: [DocumentLoadMeasurement] = []
    ) throws -> WebReadableDocument {
        let manifestURL = directory.appendingPathComponent(manifestName)
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainTextURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest = try JSONDecoder().decode(DOCXPreparedManifest.self, from: manifestData)
        guard manifest.schemaVersion == schemaVersion,
              manifest.fingerprint == fingerprint,
              manifest.title == title,
              digest(htmlURL) == manifest.htmlSHA256,
              digest(plainTextURL) == manifest.plainTextSHA256,
              digest(tocURL) == manifest.tocSHA256 else {
            throw cacheError(AppText.localized(
                "DOCX 缓存数据无效。",
                "The prepared DOCX cache entry is invalid."
            ))
        }
        let fixedBytes = fileSize(htmlURL) + fileSize(plainTextURL) + fileSize(tocURL)
        guard fixedBytes >= 0 else {
            throw cacheError(AppText.localized("DOCX 缓存文件缺失。", "A prepared DOCX cache file is missing."))
        }
        var mediaBytes: Int64 = 0
        for media in manifest.media {
            guard let safePath = EPUBPathResolver.safeArchivePath(media.path),
                  safePath == media.path,
                  fileSize(directory.appendingPathComponent(safePath)) == media.bytes else {
                throw cacheError(AppText.localized(
                    "DOCX 缓存媒体文件无效。",
                    "A prepared DOCX media file is invalid."
                ))
            }
            mediaBytes += media.bytes
        }
        guard manifest.entryBytes == fixedBytes + mediaBytes + Int64(manifestData.count) else {
            throw cacheError(AppText.localized("DOCX 缓存大小无效。", "The prepared DOCX cache size is invalid."))
        }
        let plainText = try String(contentsOf: plainTextURL, encoding: .utf8)
        let toc = try JSONDecoder().decode(
            [DOCXPreparedTOCItem].self,
            from: Data(contentsOf: tocURL, options: .mappedIfSafe)
        ).map(\.readerItem)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
        return WebReadableDocument(
            html: "",
            htmlFileURL: htmlURL,
            baseURL: directory,
            plainText: plainText,
            plainTextLoader: nil,
            coverImageURL: nil,
            tocItems: toc,
            diagnostics: [],
            ownedResource: ownedResource,
            loadMeasurements: measurements
        )
    }

    static func write(
        directory: URL,
        fingerprint: String,
        title: String,
        content: DOCXStreamingResult
    ) throws -> Int64 {
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainTextURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        let body = content.html.isEmpty
            ? "<p>\(WebDocumentLoader.escapeHTML(AppText.localized("无法读取 DOCX 内容。", "Unable to read DOCX content.")))</p>"
            : content.html
        let html = WebDocumentLoader.pageHTML(
            title: title,
            body: body,
            documentStyles: WebDocumentLoader.docxReaderStyles,
            profile: .docx
        )
        try Data(html.utf8).write(to: htmlURL, options: .atomic)
        try Data(content.plainText.joined(separator: "\n\n").utf8).write(to: plainTextURL, options: .atomic)
        try JSONEncoder().encode(content.tocItems.map(DOCXPreparedTOCItem.init)).write(to: tocURL, options: .atomic)

        let media = try mediaFiles(in: directory)
        let contentBytes = fileSize(htmlURL) + fileSize(plainTextURL) + fileSize(tocURL)
            + media.reduce(0) { $0 + $1.bytes }
        guard contentBytes >= 0 else {
            throw cacheError(AppText.localized("无法计算 DOCX 缓存大小。", "Unable to size the prepared DOCX cache."))
        }
        let base = DOCXPreparedManifest(
            schemaVersion: schemaVersion,
            fingerprint: fingerprint,
            title: title,
            entryBytes: contentBytes,
            htmlSHA256: try requiredDigest(htmlURL),
            plainTextSHA256: try requiredDigest(plainTextURL),
            tocSHA256: try requiredDigest(tocURL),
            media: media
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var manifest = base
        var data = try encoder.encode(manifest)
        for _ in 0..<5 {
            let exactBytes = contentBytes + Int64(data.count)
            guard exactBytes != manifest.entryBytes else { break }
            manifest = DOCXPreparedManifest(
                schemaVersion: base.schemaVersion,
                fingerprint: base.fingerprint,
                title: base.title,
                entryBytes: exactBytes,
                htmlSHA256: base.htmlSHA256,
                plainTextSHA256: base.plainTextSHA256,
                tocSHA256: base.tocSHA256,
                media: base.media
            )
            data = try encoder.encode(manifest)
        }
        try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
        return manifest.entryBytes
    }

    static func cleanup(root: URL, keeping key: String, policy: DOCXPreparedCachePolicy) {
        guard var entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter({ $0.lastPathComponent != key }) else { return }
        entries.sort {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        let current = root.appendingPathComponent(key, isDirectory: true)
        var totalEntries = FileManager.default.fileExists(atPath: current.path) ? 1 : 0
        var totalBytes = entryBytes(at: current)
        for entry in entries {
            totalEntries += 1
            totalBytes += entryBytes(at: entry)
        }
        while (totalEntries > policy.maximumEntries || totalBytes > policy.maximumBytes), !entries.isEmpty {
            let victim = entries.removeFirst()
            let bytes = entryBytes(at: victim)
            if (try? FileManager.default.removeItem(at: victim)) != nil {
                totalEntries -= 1
                totalBytes -= bytes
            }
        }
    }

    static func fingerprint(url: URL, cancellationToken: DocumentLoadCancellationToken?) throws -> String {
        let handle = try FileHandle(forReadingFrom: url.standardizedFileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try cancellationToken?.checkCancellation()
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func entryBytes(at directory: URL) -> Int64 {
        let manifestURL = directory.appendingPathComponent(manifestName)
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(DOCXPreparedManifest.self, from: data),
           manifest.entryBytes > 0 {
            return manifest.entryBytes
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var bytes: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return bytes
    }

    private static func mediaFiles(in directory: URL) throws -> [DOCXPreparedMediaFile] {
        let mediaRoot = directory.appendingPathComponent("word/media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mediaRoot.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: mediaRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [DOCXPreparedMediaFile] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let path = EPUBPathResolver.relativeFilePath(from: directory, to: file)
            guard EPUBPathResolver.safeArchivePath(path) == path else {
                throw cacheError(AppText.localized("DOCX 媒体路径不安全。", "A prepared DOCX media path is unsafe."), code: -3)
            }
            files.append(DOCXPreparedMediaFile(path: path, bytes: Int64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return -1 }
        return Int64(values?.fileSize ?? -1)
    }

    private static func requiredDigest(_ url: URL) throws -> String {
        let value = digest(url)
        guard !value.isEmpty else {
            throw cacheError(AppText.localized("无法校验 DOCX 缓存。", "Unable to fingerprint a prepared DOCX file."))
        }
        return value
    }

    private static func digest(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        return digest(data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheError(_ description: String, code: Int = -4) -> Error {
        NSError(domain: "LeafReader", code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
