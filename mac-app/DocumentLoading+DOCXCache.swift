import CryptoKit
import Foundation

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
    let htmlSHA256: String
    let plainTextSHA256: String
    let tocSHA256: String
    let media: [DOCXPreparedMediaFile]
}

private enum DOCXPreparedCache {
    static let schemaVersion = 1
    static let maximumEntries = 10
    static let lock = NSLock()
    static let manifestName = "manifest.json"
    static let htmlName = "rendered.html"
    static let plainTextName = "plain-text.txt"
    static let tocName = "toc.json"

    static func root() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["LEAFREADER_DOCX_CACHE_ROOT"],
           !override.isEmpty {
            let root = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = caches
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("DOCXPreparedCache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func key(fingerprint: String, title: String) -> String {
        digest(Data("\(schemaVersion)\u{0}\(fingerprint)\u{0}\(title)".utf8))
    }

    static func load(directory: URL, fingerprint: String, title: String) throws -> WebReadableDocument {
        let manifestURL = directory.appendingPathComponent(manifestName)
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainTextURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        let manifest = try JSONDecoder().decode(
            DOCXPreparedManifest.self,
            from: Data(contentsOf: manifestURL, options: .mappedIfSafe)
        )
        guard manifest.schemaVersion == schemaVersion,
              manifest.fingerprint == fingerprint,
              manifest.title == title,
              digest(htmlURL) == manifest.htmlSHA256,
              digest(plainTextURL) == manifest.plainTextSHA256,
              digest(tocURL) == manifest.tocSHA256 else {
            throw cacheError(AppText.localized("DOCX 缓存数据无效。", "The prepared DOCX cache entry is invalid."))
        }
        for media in manifest.media {
            guard let safePath = EPUBPathResolver.safeArchivePath(media.path),
                  safePath == media.path,
                  fileSize(directory.appendingPathComponent(safePath)) == media.bytes else {
                throw cacheError(AppText.localized("DOCX 缓存媒体文件无效。", "A prepared DOCX media file is invalid."))
            }
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
            ownedResource: nil
        )
    }

    static func prepare(
        sourceURL: URL,
        directory: URL,
        fingerprint: String,
        title: String,
        cancellationToken: DocumentLoadCancellationToken?
    ) throws -> WebReadableDocument {
        try cancellationToken?.checkCancellation()
        try WebDocumentLoader.unzip(
            url: sourceURL,
            to: directory,
            cancellationToken: cancellationToken
        )
        try cancellationToken?.checkCancellation()
        let relationships = try WebDocumentLoader.docxStreamingRelationships(
            from: directory.appendingPathComponent("word/_rels/document.xml.rels"),
            cancellationToken: cancellationToken
        )
        let content = try WebDocumentLoader.docxStreamingContent(
            from: directory.appendingPathComponent("word/document.xml"),
            directory: directory,
            relationships: relationships,
            mediaReferenceStyle: .relativeToPreparedEntry,
            cancellationToken: cancellationToken
        )
        try cancellationToken?.checkCancellation()
        let body = content.html.isEmpty
            ? "<p>\(WebDocumentLoader.escapeHTML(AppText.localized("无法读取 DOCX 内容。", "Unable to read DOCX content.")))</p>"
            : content.html
        let html = WebDocumentLoader.pageHTML(
            title: title,
            body: body,
            documentStyles: WebDocumentLoader.docxReaderStyles,
            profile: .docx
        )
        let plainText = content.plainText.joined(separator: "\n\n")
        let toc = content.tocItems.map(DOCXPreparedTOCItem.init)
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainTextURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        try Data(html.utf8).write(to: htmlURL, options: .atomic)
        try Data(plainText.utf8).write(to: plainTextURL, options: .atomic)
        try JSONEncoder().encode(toc).write(to: tocURL, options: .atomic)
        let manifest = DOCXPreparedManifest(
            schemaVersion: schemaVersion,
            fingerprint: fingerprint,
            title: title,
            htmlSHA256: digest(htmlURL),
            plainTextSHA256: digest(plainTextURL),
            tocSHA256: digest(tocURL),
            media: mediaFiles(in: directory)
        )
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent(manifestName),
            options: .atomic
        )
        return try load(directory: directory, fingerprint: fingerprint, title: title)
    }

    static func cleanup(root: URL, keeping key: String) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), entries.count > maximumEntries else { return }
        let stale = entries
            .filter { $0.lastPathComponent != key }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
            .prefix(entries.count - maximumEntries)
        for entry in stale {
            try? FileManager.default.removeItem(at: entry)
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

    static func digest(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        return digest(data)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func mediaFiles(in directory: URL) -> [DOCXPreparedMediaFile] {
        let mediaRoot = directory.appendingPathComponent("word/media", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: mediaRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return nil }
            let prefix = directory.standardizedFileURL.path + "/"
            guard url.standardizedFileURL.path.hasPrefix(prefix) else { return nil }
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            return DOCXPreparedMediaFile(path: path, bytes: Int64(values.fileSize ?? 0))
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return -1 }
        return Int64(values?.fileSize ?? -1)
    }

    static func cacheError(_ description: String) -> Error {
        NSError(domain: "LeafReader", code: -4, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

extension WebDocumentLoader {
    static func loadPreparedDOCX(
        url: URL,
        cancellationToken: DocumentLoadCancellationToken?
    ) throws -> WebReadableDocument {
        let title = url.deletingPathExtension().lastPathComponent
        let fingerprint = try DOCXPreparedCache.fingerprint(url: url, cancellationToken: cancellationToken)
        let root = try DOCXPreparedCache.root()
        let key = DOCXPreparedCache.key(fingerprint: fingerprint, title: title)
        let destination = root.appendingPathComponent(key, isDirectory: true)

        DOCXPreparedCache.lock.lock()
        defer { DOCXPreparedCache.lock.unlock() }
        try cancellationToken?.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                let document = try DOCXPreparedCache.load(
                    directory: destination,
                    fingerprint: fingerprint,
                    title: title
                )
                DOCXPreparedCache.cleanup(root: root, keeping: key)
                return document
            } catch {
                try? FileManager.default.removeItem(at: destination)
            }
        }

        let temporary = root.appendingPathComponent("\(key)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            _ = try DOCXPreparedCache.prepare(
                sourceURL: url,
                directory: temporary,
                fingerprint: fingerprint,
                title: title,
                cancellationToken: cancellationToken
            )
            try cancellationToken?.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            let document = try DOCXPreparedCache.load(
                directory: destination,
                fingerprint: fingerprint,
                title: title
            )
            DOCXPreparedCache.cleanup(root: root, keeping: key)
            return document
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
