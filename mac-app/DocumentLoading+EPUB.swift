import Foundation

extension WebDocumentLoader {
    // MARK: - EPUB Loading

    static func loadEPUB(url: URL) throws -> WebReadableDocument {
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
        var diagnostics: [String] = []
        for item in package.spineItems where item.isLinear {
            guard let href = package.manifest[item.id] else {
                diagnostics.append("Spine item '\(item.id)' is missing from the manifest.")
                continue
            }
            guard let chapterURL = existingEPUBResourceURL(href, relativeTo: opfDirectory, epubRootURL: directory) else {
                diagnostics.append("Chapter '\(href)' is missing or outside the EPUB container.")
                continue
            }
            let chapter: String
            do {
                chapter = try EPUBTextDecoder.text(at: chapterURL)
            } catch {
                diagnostics.append("Chapter '\(href)' could not be decoded: \(error.localizedDescription)")
                continue
            }
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

        let body = sections.isEmpty
            ? EPUBHTMLSanitizer.unreadableBody(diagnostics: diagnostics)
            : sections.joined(separator: "\n")
        let html = pageHTML(title: url.deletingPathExtension().lastPathComponent, body: body, documentStyles: "", profile: .epub)
        let htmlFileURL = opfDirectory.appendingPathComponent(".leafreader-rendered.html")
        do {
            try html.write(to: htmlFileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("LeafReader EPUB: failed to write rendered HTML at %@ (error=%@)", htmlFileURL.path, error.localizedDescription)
        }
        return WebReadableDocument(
            html: html,
            htmlFileURL: FileManager.default.fileExists(atPath: htmlFileURL.path) ? htmlFileURL : nil,
            baseURL: opfDirectory,
            plainText: "",
            plainTextLoader: { epubPlainText(from: chapterURLs) },
            coverImageURL: epubCoverImageURL(opfXML: opfXML, manifestItems: package.manifestItems, opfDirectory: opfDirectory, epubRootURL: directory),
            tocItems: epubTOCItems(opfXML: opfXML, manifest: package.manifest, opfDirectory: opfDirectory, epubRootURL: directory),
            diagnostics: diagnostics
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

    // MARK: - EPUB Text, Cover, and Resources

    static func epubPlainText(from chapterURLs: [URL]) -> String {
        chapterURLs.compactMap { url in
            guard let chapter = try? EPUBTextDecoder.text(at: url) else { return nil }
            let text = EPUBHTMLSanitizer.plainText(from: chapter)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n\n")
    }

    static func epubCoverImageURL(
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

    static func epubCoverImagePath(
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

    static func epubCoverResourceHref(
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

    static func epubFirstImageHref(in html: String) -> String? {
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

    static func isEPUBImageItem(_ item: EPUBManifestItem) -> Bool {
        item.mediaType.hasPrefix("image/") || isEPUBImagePath(item.href)
    }

    static func isEPUBImagePath(_ path: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func existingEPUBResourceURL(_ href: String, relativeTo baseURL: URL, epubRootURL: URL) -> URL? {
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

    static func relativeEPUBHref(_ href: String, relativeTo documentHref: String) -> String {
        let documentDirectory = URL(fileURLWithPath: documentHref).deletingLastPathComponent().relativePath
        guard documentDirectory != "." else { return href }
        return "\(documentDirectory)/\(href)"
    }

    static func epubZipPath(_ href: String, relativeTo opfDirectoryPath: String) -> String {
        let hrefWithoutFragment = href
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment
        let joined = opfDirectoryPath == "." || opfDirectoryPath.isEmpty ? decodedHref : "\(opfDirectoryPath)/\(decodedHref)"
        return (joined as NSString).standardizingPath
    }

    // MARK: - EPUB Table of Contents

    static func epubTOCItems(
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

    static func epubNCXTOCItems(from xml: String, baseHref: String) -> [ReaderTOCItem] {
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

    static func epubHTMLNavItems(from html: String, baseHref: String) -> [ReaderTOCItem] {
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

    static func firstXMLAttribute(_ attribute: String, in xml: String) -> String? {
        let pattern = #"\#(attribute)=["']([^"']+)["']"#
        return regexMatches(pattern, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

}
