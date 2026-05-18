import CryptoKit
import Foundation

enum ReaderDocumentKind {
    case pdf
    case epub
    case docx

    static func kind(for url: URL) -> ReaderDocumentKind? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "docx":
            return .docx
        default:
            return nil
        }
    }
}

struct WebReadableDocument {
    let html: String
    let htmlFileURL: URL?
    let baseURL: URL
    let plainText: String
    let plainTextLoader: (() -> String)?
    let coverImageURL: URL?
    let tocItems: [ReaderTOCItem]
}

struct ReaderTOCItem {
    let title: String
    let href: String
    let level: Int
}

private struct HTMLBodyFragment {
    let content: String
    let bodyClasses: String
    let bodyAttributes: String
}

private struct DOCXParagraph {
    let html: String
    let text: String
    let tag: String
    let classes: [String]
    let isListItem: Bool
}

enum WebDocumentLoader {
    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    static func load(url: URL) throws -> WebReadableDocument {
        switch ReaderDocumentKind.kind(for: url) {
        case .epub:
            return try loadEPUB(url: url)
        case .docx:
            return try loadDOCX(url: url)
        default:
            throw NSError(domain: "LeafReader", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported document type"
            ])
        }
    }

    // MARK: - EPUB Loading

    private static func loadEPUB(url: URL) throws -> WebReadableDocument {
        let directory = try unzipEPUBToCache(url: url)
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        let containerXML = try EPUBTextDecoder.text(at: containerURL)
        guard let opfPath = firstXMLAttribute("full-path", in: containerXML) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid EPUB container"
            ])
        }

        let opfURL = directory.appendingPathComponent(opfPath)
        guard EPUBPathResolver.isFileURL(opfURL, containedIn: directory) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid EPUB package path"
            ])
        }
        let opfDirectory = opfURL.deletingLastPathComponent()
        let opfXML = try EPUBTextDecoder.text(at: opfURL)
        let package = EPUBPackageParser.package(from: opfXML)
        var sections: [String] = []
        var chapterURLs: [URL] = []
        for item in package.spineItems where item.isLinear {
            guard let href = package.manifest[item.id] else { continue }
            guard let chapterURL = existingEPUBResourceURL(href, relativeTo: opfDirectory, epubRootURL: directory) else { continue }
            guard let chapter = try? EPUBTextDecoder.text(at: chapterURL) else { continue }
            chapterURLs.append(chapterURL)
            let fragment = htmlBodyFragment(from: chapter)
            let content = EPUBHTMLSanitizer.sanitizeContent(
                rewriteRelativeLinks(
                    in: fragment.content,
                    resourceBaseURL: chapterURL.deletingLastPathComponent(),
                    documentBaseURL: opfDirectory,
                    epubRootURL: directory
                )
            )
            let attributes = epubSectionAttributes(
                from: fragment.bodyAttributes,
                bodyClasses: fragment.bodyClasses,
                sectionIndex: sections.count,
                href: href,
                isCover: isEPUBCoverSection(href: href, fragment: fragment)
            )
            sections.append("<section\(attributes)>\(content)</section>")
        }

        let body = sections.isEmpty ? "<p>Unable to read EPUB content.</p>" : sections.joined(separator: "\n")
        let html = pageHTML(title: url.deletingPathExtension().lastPathComponent, body: body, documentStyles: "", profile: .epub)
        let htmlFileURL = opfDirectory.appendingPathComponent(".leafreader-rendered.html")
        try? html.write(to: htmlFileURL, atomically: true, encoding: .utf8)
        return WebReadableDocument(
            html: html,
            htmlFileURL: FileManager.default.fileExists(atPath: htmlFileURL.path) ? htmlFileURL : nil,
            baseURL: opfDirectory,
            plainText: "",
            plainTextLoader: { epubPlainText(from: chapterURLs) },
            coverImageURL: epubCoverImageURL(opfXML: opfXML, manifestItems: package.manifestItems, opfDirectory: opfDirectory, epubRootURL: directory),
            tocItems: epubTOCItems(opfXML: opfXML, manifest: package.manifest, opfDirectory: opfDirectory, epubRootURL: directory)
        )
    }

    static func coverImageData(forEPUB url: URL) throws -> Data? {
        guard let containerData = try zipEntryData(in: url, entryPath: "META-INF/container.xml"),
              let containerXML = EPUBTextDecoder.text(from: containerData),
              let opfPath = firstXMLAttribute("full-path", in: containerXML),
              let opfData = try zipEntryData(in: url, entryPath: opfPath),
              let opfXML = EPUBTextDecoder.text(from: opfData) else {
            return nil
        }
        let opfDirectoryPath = URL(fileURLWithPath: opfPath).deletingLastPathComponent().relativePath
        let package = EPUBPackageParser.package(from: opfXML)
        guard let coverPath = epubCoverImagePath(
            opfXML: opfXML,
            manifestItems: package.manifestItems,
            opfDirectoryPath: opfDirectoryPath,
            readTextAtPath: { path in
                guard let data = try? zipEntryData(in: url, entryPath: path) else { return nil }
                return EPUBTextDecoder.text(from: data)
            }
        ) else {
            return nil
        }
        return try zipEntryData(in: url, entryPath: coverPath)
    }

    // MARK: - DOCX Loading

    private static func loadDOCX(url: URL) throws -> WebReadableDocument {
        let directory = try unzip(url: url)
        let documentURL = directory.appendingPathComponent("word/document.xml")
        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        let relationships = docxRelationships(from: directory.appendingPathComponent("word/_rels/document.xml.rels"))
        let body = docxBodyHTML(from: xml, directory: directory, relationships: relationships)
        let title = url.deletingPathExtension().lastPathComponent
        let plainText = docxParagraphs(from: xml).joined(separator: "\n\n")
        return WebReadableDocument(
            html: pageHTML(title: title, body: body.isEmpty ? "<p>Unable to read DOCX content.</p>" : body, documentStyles: docxReaderStyles, profile: .docx),
            htmlFileURL: nil,
            baseURL: directory,
            plainText: plainText,
            plainTextLoader: nil,
            coverImageURL: nil,
            tocItems: docxTOCItems(from: body)
        )
    }

    // MARK: - Archive and Text Decoding

    private static func unzipEPUBToCache(url: URL) throws -> URL {
        let fileURL = url.standardizedFileURL
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let key = SHA256.hash(data: Data("\(fileURL.path)#\(modified)#\(fileSize)".utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let cacheRoot = try epubCacheRoot()
        cleanupOldEPUBCacheEntries(in: cacheRoot, keeping: key)
        let destination = cacheRoot.appendingPathComponent(key, isDirectory: true)
        let containerURL = destination.appendingPathComponent("META-INF/container.xml")
        if FileManager.default.fileExists(atPath: containerURL.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return destination
        }

        let temporaryDestination = cacheRoot.appendingPathComponent("\(key)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDestination, withIntermediateDirectories: true)
        do {
            try unzip(url: fileURL, to: temporaryDestination)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryDestination, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporaryDestination)
            throw error
        }
    }

    private static func epubCacheRoot() throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cacheRoot = root
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("EPUBCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        return cacheRoot
    }

    private static func cleanupOldEPUBCacheEntries(in cacheRoot: URL, keeping currentKey: String) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), entries.count > 10 else {
            return
        }
        let staleEntries = entries
            .filter { $0.lastPathComponent != currentKey }
            .sorted {
                let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
            .prefix(max(0, entries.count - 10))
        for entry in staleEntries {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func unzip(url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try unzip(url: url, to: destination)
        return destination
    }

    private static func unzip(url: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LeafReader", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Unable to unpack \(url.lastPathComponent)"
            ])
        }
    }

    private static func zipEntryData(in url: URL, entryPath: String) throws -> Data? {
        guard let entryPath = EPUBPathResolver.safeArchivePath(entryPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entryPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: - EPUB Text, Cover, and Resources

    private static func epubPlainText(from chapterURLs: [URL]) -> String {
        chapterURLs.compactMap { url in
            guard let chapter = try? EPUBTextDecoder.text(at: url) else { return nil }
            let text = EPUBHTMLSanitizer.plainText(from: chapter)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n\n")
    }

    private static func epubCoverImageURL(
        opfXML: String,
        manifestItems: [EPUBManifestItem],
        opfDirectory: URL,
        epubRootURL: URL
    ) -> URL? {
        epubCoverResourceHref(
            opfXML: opfXML,
            manifestItems: manifestItems,
            resolveImage: { href in
                existingEPUBResourceURL(href, relativeTo: opfDirectory, epubRootURL: epubRootURL)?.path
            },
            readText: { href in
                guard let url = existingEPUBResourceURL(href, relativeTo: opfDirectory, epubRootURL: epubRootURL) else { return nil }
                return try? EPUBTextDecoder.text(at: url)
            },
            nestedImageHref: epubFirstImageHref
        ).flatMap { existingEPUBResourceURL($0, relativeTo: opfDirectory, epubRootURL: epubRootURL) }
    }

    private static func epubCoverImagePath(
        opfXML: String,
        manifestItems: [EPUBManifestItem],
        opfDirectoryPath: String,
        readTextAtPath: (String) -> String?
    ) -> String? {
        epubCoverResourceHref(
            opfXML: opfXML,
            manifestItems: manifestItems,
            resolveImage: { href in
                let path = epubZipPath(href, relativeTo: opfDirectoryPath)
                return isEPUBImagePath(path) ? path : nil
            },
            readText: { href in readTextAtPath(epubZipPath(href, relativeTo: opfDirectoryPath)) },
            nestedImageHref: epubFirstImageHref
        ).map { epubZipPath($0, relativeTo: opfDirectoryPath) }
    }

    private static func epubCoverResourceHref(
        opfXML: String,
        manifestItems: [EPUBManifestItem],
        resolveImage: (String) -> String?,
        readText: (String) -> String?,
        nestedImageHref: (String) -> String?
    ) -> String? {
        var itemsByID: [String: EPUBManifestItem] = [:]
        for item in manifestItems where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        let imageItems = manifestItems.filter(isEPUBImageItem)

        for tag in regexMatches(#"<meta\b[^>]*?/?>"#, in: opfXML).compactMap(\.first) {
            guard (firstXMLAttribute("name", in: tag) ?? "").caseInsensitiveCompare("cover") == .orderedSame,
                  let coverID = firstXMLAttribute("content", in: tag),
                  let item = itemsByID[coverID] else { continue }
            if isEPUBImageItem(item) {
                if resolveImage(item.href) != nil {
                    return item.href
                }
                continue
            }
            if let html = readText(item.href), let nested = nestedImageHref(html) {
                return relativeEPUBHref(nested, relativeTo: item.href)
            }
        }

        for item in imageItems where item.properties.contains("cover-image") {
            if resolveImage(item.href) != nil {
                return item.href
            }
        }

        for item in imageItems
            where item.id.localizedCaseInsensitiveContains("cover")
                || item.href.localizedCaseInsensitiveContains("cover") {
            if resolveImage(item.href) != nil {
                return item.href
            }
        }

        for tag in regexMatches(#"<reference\b[^>]*?/?>"#, in: opfXML).compactMap(\.first) {
            guard (firstXMLAttribute("type", in: tag) ?? "").lowercased().contains("cover"),
                  let href = firstXMLAttribute("href", in: tag) else { continue }
            if resolveImage(href) != nil {
                return href
            }
            if let html = readText(href), let nested = nestedImageHref(html) {
                return relativeEPUBHref(nested, relativeTo: href)
            }
        }

        for item in imageItems {
            if resolveImage(item.href) != nil {
                return item.href
            }
        }

        return nil
    }

    private static func epubFirstImageHref(in html: String) -> String? {
        let imageTags = regexMatches(#"(?i)<(?:img|image)\b[^>]*?/?>"#, in: html).compactMap(\.first)
        for tag in imageTags {
            let href = firstXMLAttribute("src", in: tag)
                ?? firstXMLAttribute("href", in: tag)
                ?? firstXMLAttribute("xlink:href", in: tag)
            guard let href, isEPUBImagePath(href) else { continue }
            return href
        }
        return nil
    }

    private static func isEPUBImageItem(_ item: EPUBManifestItem) -> Bool {
        item.mediaType.hasPrefix("image/") || isEPUBImagePath(item.href)
    }

    private static func isEPUBImagePath(_ path: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func existingEPUBResourceURL(_ href: String, relativeTo baseURL: URL, epubRootURL: URL) -> URL? {
        let hrefWithoutFragment = href
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        guard !hrefWithoutFragment.isEmpty,
              !hrefWithoutFragment.lowercased().hasPrefix("data:") else { return nil }
        let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment
        let url = baseURL.appendingPathComponent(decodedHref).standardizedFileURL
        guard EPUBPathResolver.isFileURL(url, containedIn: epubRootURL) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func relativeEPUBHref(_ href: String, relativeTo documentHref: String) -> String {
        let documentDirectory = URL(fileURLWithPath: documentHref).deletingLastPathComponent().relativePath
        guard documentDirectory != "." else { return href }
        return "\(documentDirectory)/\(href)"
    }

    private static func epubZipPath(_ href: String, relativeTo opfDirectoryPath: String) -> String {
        let hrefWithoutFragment = href
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment
        let joined = opfDirectoryPath == "." || opfDirectoryPath.isEmpty ? decodedHref : "\(opfDirectoryPath)/\(decodedHref)"
        return (joined as NSString).standardizingPath
    }

    // MARK: - EPUB Table of Contents

    private static func epubTOCItems(
        opfXML: String,
        manifest: [String: String],
        opfDirectory: URL,
        epubRootURL: URL
    ) -> [ReaderTOCItem] {
        let ncxByMediaType = regexMatches(
            #"<item\b[^>]*\bmedia-type=["']application/x-dtbncx\+xml["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>"#,
            in: opfXML
        ).first.flatMap { $0.count > 1 ? $0[1] : nil }
        let ncxByExtension = regexMatches(
            #"<item\b[^>]*\bhref=["']([^"']+\.ncx)["'][^>]*/?>"#,
            in: opfXML
        ).first.flatMap { $0.count > 1 ? $0[1] : nil }
        let ncxHref = manifest["ncx"] ?? ncxByMediaType ?? ncxByExtension
        if let ncxHref {
            if let ncxURL = existingEPUBResourceURL(ncxHref, relativeTo: opfDirectory, epubRootURL: epubRootURL),
               let ncx = try? EPUBTextDecoder.text(at: ncxURL) {
                let items = epubNCXTOCItems(from: ncx, baseHref: ncxHref)
                if !items.isEmpty { return items }
            }
        }

        let navHref = regexMatches(#"<item\b[^>]*?/?>"#, in: opfXML)
            .compactMap(\.first)
            .first(where: { (firstXMLAttribute("properties", in: $0) ?? "").contains("nav") })
            .flatMap { firstXMLAttribute("href", in: $0) }
        if let navHref {
            if let navURL = existingEPUBResourceURL(navHref, relativeTo: opfDirectory, epubRootURL: epubRootURL),
               let nav = try? EPUBTextDecoder.text(at: navURL) {
                return epubHTMLNavItems(from: nav, baseHref: navHref)
            }
        }
        return []
    }

    private static func epubNCXTOCItems(from xml: String, baseHref: String) -> [ReaderTOCItem] {
        guard let tagRegex = cachedRegex(#"(?i)</?navPoint\b[^>]*>"#) else { return [] }
        let nsXML = xml as NSString
        var items: [(location: Int, item: ReaderTOCItem)] = []
        var stack: [(start: Int, level: Int)] = []
        for match in tagRegex.matches(in: xml, range: NSRange(location: 0, length: nsXML.length)) {
            let tag = nsXML.substring(with: match.range)
            if tag.hasPrefix("</") {
                guard let point = stack.popLast() else { continue }
                let navPointRange = NSRange(
                    location: point.start,
                    length: match.range.location + match.range.length - point.start
                )
                let navPoint = nsXML.substring(with: navPointRange)
                let title = regexMatches(#"<text\b[^>]*>([\s\S]*?)</text>"#, in: navPoint)
                    .first
                    .flatMap { $0.count > 1 ? EPUBHTMLSanitizer.plainText(from: $0[1]) : nil } ?? ""
                let contentTag = regexMatches(#"<content\b[^>]*/?>"#, in: navPoint).first?.first ?? ""
                let src = firstXMLAttribute("src", in: contentTag) ?? ""
                guard !title.isEmpty, !src.isEmpty else { continue }
                items.append((
                    location: point.start,
                    item: ReaderTOCItem(
                        title: title,
                        href: EPUBPathResolver.normalizedTOCHref(src, relativeTo: baseHref),
                        level: min(point.level, 4)
                    )
                ))
            } else if !tag.hasSuffix("/>") {
                stack.append((start: match.range.location, level: stack.count))
            }
        }
        return items.sorted { $0.location < $1.location }.map(\.item)
    }

    private static func epubHTMLNavItems(from html: String, baseHref: String) -> [ReaderTOCItem] {
        guard let tokenRegex = cachedRegex(
            #"(?i)<(/?)(?:ol|ul)\b[^>]*>|<a\b[^>]*\bhref=["']([^"']+)["'][^>]*>"#
        ) else { return [] }
        let nsHTML = html as NSString
        var items: [ReaderTOCItem] = []
        var listDepth = 0
        for match in tokenRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let token = nsHTML.substring(with: match.range)
            if token.range(of: #"(?i)^</"#, options: .regularExpression) != nil {
                listDepth = max(0, listDepth - 1)
                continue
            }
            if token.range(of: #"(?i)^<(?:ol|ul)\b"#, options: .regularExpression) != nil {
                listDepth += 1
                continue
            }
            guard match.numberOfRanges > 2,
                  match.range(at: 2).location != NSNotFound else { continue }
            let href = nsHTML.substring(with: match.range(at: 2))
            let afterAnchor = NSRange(
                location: match.range.location + match.range.length,
                length: nsHTML.length - match.range.location - match.range.length
            )
            let closeRange = nsHTML.range(of: "</a>", options: [.caseInsensitive], range: afterAnchor)
            guard closeRange.location != NSNotFound else { continue }
            let titleRange = NSRange(location: afterAnchor.location, length: closeRange.location - afterAnchor.location)
            let title = EPUBHTMLSanitizer.plainText(from: nsHTML.substring(with: titleRange))
            guard !title.isEmpty else { continue }
            items.append(ReaderTOCItem(
                title: title,
                href: EPUBPathResolver.normalizedTOCHref(href, relativeTo: baseHref),
                level: min(max(0, listDepth - 1), 4)
            ))
        }
        return items
    }

    private static func firstXMLAttribute(_ attribute: String, in xml: String) -> String? {
        let pattern = #"\#(attribute)=["']([^"']+)["']"#
        return regexMatches(pattern, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    // MARK: - DOCX Rendering

    private static func docxParagraphs(from xml: String) -> [String] {
        let paragraphMatches = regexMatches(#"<w:p\b[\s\S]*?</w:p>"#, in: xml).compactMap(\.first)
        return paragraphMatches.map { paragraph in
            regexMatches(#"<w:t\b[^>]*>([\s\S]*?)</w:t>"#, in: paragraph)
                .compactMap { $0.count > 1 ? EPUBHTMLSanitizer.decodeEntities($0[1]) : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static let docxReaderStyles = """
            .docx-document { max-width: 760px; margin: 0 auto; }
            .docx-document h1 { font-size: 1.72em; margin: 0 0 1.1em; color: #1f3f68; font-weight: 760; line-height: 1.28; }
            .docx-document h2 { font-size: 1.34em; margin: 1.75em 0 .72em; color: #245b8f; font-weight: 720; line-height: 1.32; }
            .docx-document h3 { font-size: 1.16em; margin: 1.45em 0 .55em; color: #2d5f8a; font-weight: 680; line-height: 1.35; }
            .docx-document p { margin: 0 0 .88em; line-height: 1.82; }
            .docx-document .docx-align-center { text-align: center; }
            .docx-document .docx-align-right { text-align: right; }
            .docx-document .docx-align-justify { text-align: justify; }
            .docx-document ul { margin: .2em 0 1em 1.35em; padding: 0; }
            .docx-document li { margin: .18em 0; line-height: 1.76; }
            .docx-document table { width: 100%; border-collapse: collapse; margin: 1.2em 0 1.5em; font-size: .95em; }
            .docx-document td, .docx-document th { border: 1px solid #d7dde8; padding: .55em .7em; vertical-align: top; }
            .docx-document tr:first-child td { background: #f1f5f9; font-weight: 650; }
            .docx-document img { max-width: min(100%, 680px); height: auto; margin: 1.2em auto; }
            """

    private static func docxBodyHTML(from xml: String, directory: URL, relationships: [String: String]) -> String {
        let body = regexMatches(#"<w:body\b[^>]*>([\s\S]*?)</w:body>"#, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil } ?? xml
        var output: [String] = ["<main class=\"docx-document\">"]
        var listOpen = false
        var headingIndex = 0

        for block in docxTopLevelBlocks(from: body) {
            if block.hasPrefix("<w:tbl") {
                if listOpen {
                    output.append("</ul>")
                    listOpen = false
                }
                output.append(docxTableHTML(from: block, directory: directory, relationships: relationships))
                continue
            }

            let paragraph = docxParagraphHTML(from: block, directory: directory, relationships: relationships)
            guard !paragraph.text.isEmpty || paragraph.html.contains("<img") else { continue }
            if paragraph.isListItem {
                if !listOpen {
                    output.append("<ul>")
                    listOpen = true
                }
                output.append("<li>\(paragraph.html)</li>")
            } else {
                if listOpen {
                    output.append("</ul>")
                    listOpen = false
                }
                let classAttribute = paragraph.classes.isEmpty ? "" : " class=\"\(escapeHTML(paragraph.classes.joined(separator: " ")))\""
                if paragraph.tag.hasPrefix("h") {
                    headingIndex += 1
                    output.append("<\(paragraph.tag) id=\"docx-heading-\(headingIndex)\"\(classAttribute)>\(paragraph.html)</\(paragraph.tag)>")
                } else {
                    output.append("<\(paragraph.tag)\(classAttribute)>\(paragraph.html)</\(paragraph.tag)>")
                }
            }
        }

        if listOpen {
            output.append("</ul>")
        }
        output.append("</main>")
        return output.joined(separator: "\n")
    }

    private static func docxTopLevelBlocks(from body: String) -> [String] {
        let nsBody = body as NSString
        var blocks: [String] = []
        var cursor = 0
        while cursor < nsBody.length {
            let remaining = NSRange(location: cursor, length: nsBody.length - cursor)
            let pRange = nsBody.range(of: "<w:p", options: [], range: remaining)
            let tblRange = nsBody.range(of: "<w:tbl", options: [], range: remaining)
            let candidates = [pRange, tblRange].filter { $0.location != NSNotFound }
            guard let start = candidates.min(by: { $0.location < $1.location }) else { break }
            let isTable = nsBody.substring(with: NSRange(location: start.location, length: min(6, nsBody.length - start.location))).hasPrefix("<w:tbl")
            let closeTag = isTable ? "</w:tbl>" : "</w:p>"
            let closeRange = nsBody.range(of: closeTag, options: [], range: NSRange(location: start.location, length: nsBody.length - start.location))
            guard closeRange.location != NSNotFound else { break }
            let end = closeRange.location + closeRange.length
            blocks.append(nsBody.substring(with: NSRange(location: start.location, length: end - start.location)))
            cursor = end
        }
        return blocks
    }

    private static func docxTableHTML(from table: String, directory: URL, relationships: [String: String]) -> String {
        let rows = regexMatches(#"<w:tr\b[\s\S]*?</w:tr>"#, in: table).compactMap(\.first)
        let htmlRows = rows.map { row in
            let cells = regexMatches(#"<w:tc\b[\s\S]*?</w:tc>"#, in: row).compactMap(\.first)
            let htmlCells = cells.map { cell -> String in
                let paragraphs = regexMatches(#"<w:p\b[\s\S]*?</w:p>"#, in: cell)
                    .compactMap(\.first)
                    .map { docxParagraphHTML(from: $0, directory: directory, relationships: relationships) }
                    .filter { !$0.text.isEmpty || $0.html.contains("<img") }
                    .map { "<p>\($0.html)</p>" }
                    .joined()
                return "<td>\(paragraphs)</td>"
            }.joined()
            return "<tr>\(htmlCells)</tr>"
        }.joined()
        return "<table>\(htmlRows)</table>"
    }

    private static func docxParagraphHTML(from paragraph: String, directory: URL, relationships: [String: String]) -> DOCXParagraph {
        let style = firstXMLAttribute("w:val", in: regexMatches(#"<w:pStyle\b[^>]*/?>"#, in: paragraph).first?.first ?? "") ?? ""
        let alignment = firstXMLAttribute("w:val", in: regexMatches(#"<w:jc\b[^>]*/?>"#, in: paragraph).first?.first ?? "")
        let runs = regexMatches(#"<w:hyperlink\b[\s\S]*?</w:hyperlink>|<w:r\b[\s\S]*?</w:r>"#, in: paragraph).compactMap(\.first)
        var html = runs.map { docxInlineHTML(from: $0, directory: directory, relationships: relationships) }.joined()
        var text = EPUBHTMLSanitizer.plainText(from: html)
        var isListItem = paragraph.contains("<w:numPr") || style.localizedCaseInsensitiveContains("List")

        if text.hasPrefix("- ") || text.hasPrefix("• ") {
            html = String(html.dropFirst(2))
            text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            isListItem = true
        }

        var classes: [String] = []
        switch alignment {
        case "center":
            classes.append("docx-align-center")
        case "right":
            classes.append("docx-align-right")
        case "both":
            classes.append("docx-align-justify")
        default:
            break
        }

        let tag: String
        if style.localizedCaseInsensitiveContains("Heading1") || style.localizedCaseInsensitiveContains("Title") {
            tag = "h1"
        } else if style.localizedCaseInsensitiveContains("Heading2") {
            tag = "h2"
        } else if style.localizedCaseInsensitiveContains("Heading3") {
            tag = "h3"
        } else {
            tag = "p"
        }

        return DOCXParagraph(html: html, text: text, tag: tag, classes: classes, isListItem: isListItem)
    }

    private static func docxInlineHTML(from runOrHyperlink: String, directory: URL, relationships: [String: String]) -> String {
        if runOrHyperlink.hasPrefix("<w:hyperlink") {
            let rid = firstXMLAttribute("r:id", in: runOrHyperlink)
            let inner = regexMatches(#"<w:r\b[\s\S]*?</w:r>"#, in: runOrHyperlink).compactMap(\.first)
                .map { docxInlineHTML(from: $0, directory: directory, relationships: relationships) }
                .joined()
            if let rid, let target = relationships[rid] {
                return "<a href=\"\(escapeHTML(target))\">\(inner)</a>"
            }
            return inner
        }

        var parts: [String] = []
        let tokens = regexMatches(#"<w:t\b[^>]*>[\s\S]*?</w:t>|<w:tab\s*/>|<w:br\s*/>|<w:drawing\b[\s\S]*?</w:drawing>"#, in: runOrHyperlink).compactMap(\.first)
        for token in tokens {
            if token.hasPrefix("<w:t") {
                let text = regexMatches(#"<w:t\b[^>]*>([\s\S]*?)</w:t>"#, in: token).first.flatMap { $0.count > 1 ? $0[1] : nil } ?? ""
                parts.append(escapeHTML(EPUBHTMLSanitizer.decodeEntities(text)))
            } else if token.hasPrefix("<w:tab") {
                parts.append("&emsp;")
            } else if token.hasPrefix("<w:br") {
                parts.append("<br>")
            } else if let rid = firstXMLAttribute("r:embed", in: token), let src = docxMediaURL(for: rid, directory: directory, relationships: relationships) {
                parts.append("<img src=\"\(escapeHTML(src.absoluteString))\">")
            }
        }

        var html = parts.joined()
        if html.isEmpty { return "" }
        if runOrHyperlink.contains("<w:b") {
            html = "<strong>\(html)</strong>"
        }
        if runOrHyperlink.contains("<w:i") {
            html = "<em>\(html)</em>"
        }
        if runOrHyperlink.contains("<w:u") {
            html = "<u>\(html)</u>"
        }
        return html
    }

    private static func docxMediaURL(for relationshipID: String, directory: URL, relationships: [String: String]) -> URL? {
        guard let target = relationships[relationshipID] else { return nil }
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            return URL(string: target)
        }
        return directory.appendingPathComponent("word").appendingPathComponent(target)
    }

    private static func docxRelationships(from url: URL) -> [String: String] {
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var relationships: [String: String] = [:]
        let pattern = #"<Relationship\b[^>]*\bId=["']([^"']+)["'][^>]*\bTarget=["']([^"']+)["'][^>]*/?>"#
        for match in regexMatches(pattern, in: xml) where match.count > 2 {
            relationships[match[1]] = EPUBHTMLSanitizer.decodeEntities(match[2])
        }
        return relationships
    }

    private static func docxTOCItems(from bodyHTML: String) -> [ReaderTOCItem] {
        var index = 0
        return regexMatches(#"<h([1-3])\b[^>]*>([\s\S]*?)</h\1>"#, in: bodyHTML).compactMap { match in
            guard match.count > 2, let headingLevel = Int(match[1]) else { return nil }
            let title = EPUBHTMLSanitizer.plainText(from: match[2])
            guard !title.isEmpty else { return nil }
            index += 1
            return ReaderTOCItem(title: title, href: "#docx-heading-\(index)", level: headingLevel - 1)
        }
    }

    // MARK: - HTML Rewriting and Sanitizing

    private static func rewriteRelativeLinks(
        in html: String,
        resourceBaseURL: URL,
        documentBaseURL: URL,
        epubRootURL: URL
    ) -> String {
        var output = html
        output = rewriteHTMLAttributeURLs(
            in: output,
            attributePattern: #"(?i)\bsrc=(["'])(?![a-z]+:|#|/)([^"']+)\1"#,
            resourceBaseURL: resourceBaseURL,
            documentBaseURL: documentBaseURL,
            epubRootURL: epubRootURL
        )
        output = rewriteHTMLAttributeURLs(
            in: output,
            attributePattern: #"(?i)\b(xlink:href|href)=(["'])(?![a-z]+:|#|/)([^"']+\.(?:jpe?g|png|gif|webp|svg))\2"#,
            resourceBaseURL: resourceBaseURL,
            documentBaseURL: documentBaseURL,
            epubRootURL: epubRootURL
        )
        output = rewriteEPUBInternalLinks(in: output, resourceBaseURL: resourceBaseURL, documentBaseURL: documentBaseURL, epubRootURL: epubRootURL)
        return output
    }

    private static func rewriteHTMLAttributeURLs(
        in html: String,
        attributePattern: String,
        resourceBaseURL: URL,
        documentBaseURL: URL,
        epubRootURL: URL
    ) -> String {
        guard let regex = cachedRegex(attributePattern) else { return html }
        let nsHTML = html as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            output += nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let fullMatch = nsHTML.substring(with: match.range)
            let attributeName: String
            let quote: String
            let value: String
            if match.numberOfRanges == 3 {
                attributeName = "src"
                quote = nsHTML.substring(with: match.range(at: 1))
                value = nsHTML.substring(with: match.range(at: 2))
            } else {
                attributeName = nsHTML.substring(with: match.range(at: 1))
                quote = nsHTML.substring(with: match.range(at: 2))
                value = nsHTML.substring(with: match.range(at: 3))
            }
            if let rewritten = epubResourcePath(
                value,
                resourceBaseURL: resourceBaseURL,
                documentBaseURL: documentBaseURL,
                epubRootURL: epubRootURL
            ) {
                output += "\(attributeName)=\(quote)\(rewritten)\(quote)"
            } else {
                output += fullMatch
            }
            cursor = match.range.location + match.range.length
        }
        output += nsHTML.substring(from: cursor)
        return output
    }

    private static func rewriteEPUBInternalLinks(
        in html: String,
        resourceBaseURL: URL,
        documentBaseURL: URL,
        epubRootURL: URL
    ) -> String {
        guard let regex = cachedRegex(#"(?i)\bhref=(["'])(?![a-z]+:|#|/)([^"']+)\1"#) else { return html }
        let nsHTML = html as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            output += nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let fullMatch = nsHTML.substring(with: match.range)
            let quote = nsHTML.substring(with: match.range(at: 1))
            let value = nsHTML.substring(with: match.range(at: 2))
            if let leafHref = EPUBPathResolver.internalLinkTarget(
                value,
                resourceBaseURL: resourceBaseURL,
                documentBaseURL: documentBaseURL,
                epubRootURL: epubRootURL
            ) {
                output += "href=\(quote)#\(quote) data-leaf-href=\(quote)\(escapeHTML(leafHref))\(quote)"
            } else {
                output += fullMatch
            }
            cursor = match.range.location + match.range.length
        }
        output += nsHTML.substring(from: cursor)
        return output
    }

    private static func epubResourcePath(
        _ href: String,
        resourceBaseURL: URL,
        documentBaseURL: URL,
        epubRootURL: URL
    ) -> String? {
        EPUBPathResolver.resourcePath(
            href,
            resourceBaseURL: resourceBaseURL,
            documentBaseURL: documentBaseURL,
            epubRootURL: epubRootURL,
            allowedCharacters: epubPathAllowedCharacters
        )
    }

    private static var epubPathAllowedCharacters: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert("/")
        allowed.remove(charactersIn: "#?")
        return allowed
    }

    private static func htmlBodyFragment(from html: String) -> HTMLBodyFragment {
        let pattern = #"<body\b([^>]*)>([\s\S]*?)</body>"#
        if let body = regexMatches(pattern, in: html).first, body.count > 2 {
            return HTMLBodyFragment(
                content: body[2],
                bodyClasses: bodyClasses(from: body[1]),
                bodyAttributes: body[1]
            )
        }
        return HTMLBodyFragment(
            content: html
                .replacingOccurrences(of: #"(?i)<!doctype[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)</?html[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)<head\b[\s\S]*?</head>"#, with: "", options: .regularExpression),
            bodyClasses: "",
            bodyAttributes: ""
        )
    }

    private static func bodyClasses(from attributes: String) -> String {
        let pattern = #"\bclass=["']([^"']+)["']"#
        return regexMatches(pattern, in: attributes).first.flatMap { $0.count > 1 ? $0[1] : nil } ?? ""
    }

    private static func epubSectionAttributes(
        from bodyAttributes: String,
        bodyClasses: String,
        sectionIndex: Int,
        href: String,
        isCover: Bool
    ) -> String {
        let classes = ["reader-section", bodyClasses].filter { !$0.isEmpty }.joined(separator: " ")
        var attributes = [
            "id=\"leaf-epub-section-\(sectionIndex)\"",
            "class=\"\(escapeHTML(classes))\"",
            "data-leaf-href=\"\(escapeHTML(hrefWithoutFragment(href)))\""
        ]
        if isCover {
            attributes.append("data-leaf-cover=\"true\"")
        }
        for name in ["style", "lang", "xml:lang", "dir"] {
            if let value = firstXMLAttribute(name, in: bodyAttributes), !value.isEmpty {
                attributes.append("\(name)=\"\(escapeHTML(value))\"")
            }
        }
        return " " + attributes.joined(separator: " ")
    }

    private static func isEPUBCoverSection(href: String, fragment: HTMLBodyFragment) -> Bool {
        let lowerHref = href.lowercased()
        if lowerHref.contains("cover") || lowerHref.contains("titlepage") {
            return true
        }
        let lowerBody = [
            fragment.bodyAttributes,
            fragment.bodyClasses,
            String(fragment.content.prefix(600))
        ].joined(separator: " ").lowercased()
        return lowerBody.contains("id=\"cover\"")
            || lowerBody.contains("id='cover'")
            || lowerBody.contains("class=\"cover")
            || lowerBody.contains("class='cover")
    }

    private static func hrefWithoutFragment(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
    }

    // MARK: - Page Rendering

    private enum PageProfile {
        case epub
        case docx

        var htmlClass: String {
            switch self {
            case .epub:
                return "reader-epub"
            case .docx:
                return "reader-docx"
            }
        }

        var profileStyles: String {
            switch self {
            case .epub:
                return """
            .reader-section { display: block; }
            .reader-section + .reader-section { margin-top: 0; padding-top: max(34em, 58vh); }
            .reader-section, .reader-section * { box-sizing: border-box; max-width: 100%; }
            .reader-section section,
            .reader-section article,
            .reader-section aside,
            .reader-section div,
            .reader-section p,
            .reader-section ul,
            .reader-section ol,
            .reader-section li,
            .reader-section dl,
            .reader-section dt,
            .reader-section dd,
            .reader-section blockquote,
            .reader-section figure,
            .reader-section figcaption,
            .reader-section table,
            .reader-section pre {
              position: static !important;
              float: none !important;
              clear: both;
              height: auto !important;
              min-height: 0 !important;
              max-height: none !important;
              overflow: visible;
            }
            .reader-section p,
            .reader-section li,
            .reader-section dd,
            .reader-section dt {
              line-height: 1.72 !important;
              min-height: 0 !important;
            }
            .reader-section pre {
              display: block !important;
              overflow-x: auto !important;
              overflow-y: visible !important;
              white-space: pre-wrap !important;
              line-height: 1.5 !important;
              padding: .7em .9em;
              border-radius: 6px;
              background: #f6f8fb;
            }
            .reader-section code {
              white-space: pre-wrap !important;
              overflow-wrap: anywhere;
            }
            .reader-section sup { position: relative !important; top: -.5em; line-height: 0; }
            .reader-section sub { position: relative !important; bottom: -.25em; line-height: 0; }
            .reader-section a[data-type="indexterm"] { display: none !important; }
            .reader-section .popup,
            .reader-section .mfp-bg,
            .reader-section .mfp-wrap,
            .reader-section .mfp-container,
            .reader-section .annotator-wrapper,
            .reader-section .topnav,
            .reader-section .gen-nav,
            .reader-section .interface-controls {
              display: none !important;
            }
            .reader-epub img, .reader-epub svg { max-width: 100%; height: auto; }
            .reader-epub a { color: inherit; text-decoration-thickness: .08em; text-underline-offset: .16em; }
            """
            case .docx:
                return ""
            }
        }
    }

    private static func pageHTML(title: String, body: String, documentStyles: String = "", profile: PageProfile = .epub) -> String {
        """
        <!doctype html>
        <html class="\(profile.htmlClass)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html { background: #f6f8fb; }
            :root { --reader-zoom: 1; }
            body { box-sizing: border-box; width: min(820px, calc(100vw - 144px)); min-height: 100vh; margin: 0 auto; padding: 56px 72px 96px; color: #191b20; background: white; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; font-size: calc(18px * var(--reader-zoom)); line-height: 1.72; overflow-wrap: break-word; }
            img, svg { max-width: 100%; height: auto; }
            ::selection { background: rgba(255, 221, 87, .62); }
            @media (max-width: 760px) { body { width: calc(100vw - 32px); padding: 36px 32px 72px; } }

            \(documentStyles)

            \(profile.profileStyles)
          </style>
          <title>\(escapeHTML(title))</title>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    // MARK: - Shared String Helpers

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = cachedRegex(pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCacheLock.lock()
        if let regex = regexCache[pattern] {
            regexCacheLock.unlock()
            return regex
        }
        regexCacheLock.unlock()

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        regexCacheLock.lock()
        regexCache[pattern] = regex
        regexCacheLock.unlock()
        return regex
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
