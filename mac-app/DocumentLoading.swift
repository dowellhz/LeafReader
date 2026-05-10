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
    let baseURL: URL
    let plainText: String
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

    private static func loadEPUB(url: URL) throws -> WebReadableDocument {
        let directory = try unzip(url: url)
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        let containerXML = try String(contentsOf: containerURL, encoding: .utf8)
        guard let opfPath = firstXMLAttribute("full-path", in: containerXML) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid EPUB container"
            ])
        }

        let opfURL = directory.appendingPathComponent(opfPath)
        let opfDirectory = opfURL.deletingLastPathComponent()
        let opfXML = try String(contentsOf: opfURL, encoding: .utf8)
        let manifest = epubManifest(from: opfXML)
        let spineIDs = epubSpineIDs(from: opfXML)
        var embeddedStyles = [epubStylesheets(from: opfXML, opfDirectory: opfDirectory)]
        var seenInlineStyles = Set<String>()

        var sections: [String] = []
        var plainTextParts: [String] = []
        for id in spineIDs {
            guard let href = manifest[id] else { continue }
            let chapterURL = opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let chapter = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }
            for style in epubInlineStyles(from: chapter, baseURL: chapterURL.deletingLastPathComponent()) where seenInlineStyles.insert(style).inserted {
                embeddedStyles.append(style)
            }
            let fragment = htmlBodyFragment(from: chapter)
            let content = rewriteRelativeLinks(in: fragment.content, baseURL: chapterURL.deletingLastPathComponent())
            let attributes = epubSectionAttributes(from: fragment.bodyAttributes, bodyClasses: fragment.bodyClasses)
            sections.append("<section\(attributes)>\(content)</section>")
            plainTextParts.append(htmlToPlainText(chapter))
        }

        let body = sections.isEmpty ? "<p>Unable to read EPUB content.</p>" : sections.joined(separator: "\n")
        return WebReadableDocument(
            html: pageHTML(title: url.deletingPathExtension().lastPathComponent, body: body, documentStyles: embeddedStyles.joined(separator: "\n\n"), profile: .epub),
            baseURL: opfDirectory,
            plainText: plainTextParts.joined(separator: "\n\n"),
            coverImageURL: epubCoverImageURL(opfXML: opfXML, manifest: manifest, opfDirectory: opfDirectory),
            tocItems: epubTOCItems(opfXML: opfXML, manifest: manifest, opfDirectory: opfDirectory)
        )
    }

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
            baseURL: directory,
            plainText: plainText,
            coverImageURL: nil,
            tocItems: docxTOCItems(from: body)
        )
    }

    private static func unzip(url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

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
        return destination
    }

    private static func epubManifest(from xml: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"<item\b[^>]*\bid=["']([^"']+)["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>"#
        for match in regexMatches(pattern, in: xml) where match.count >= 3 {
            result[match[1]] = match[2]
        }
        return result
    }

    private static func epubSpineIDs(from xml: String) -> [String] {
        let pattern = #"<itemref\b[^>]*\bidref=["']([^"']+)["'][^>]*/?>"#
        return regexMatches(pattern, in: xml).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func epubCoverImageURL(opfXML: String, manifest: [String: String], opfDirectory: URL) -> URL? {
        if let metaCoverID = regexMatches(#"<meta\b[^>]*\bname=["']cover["'][^>]*\bcontent=["']([^"']+)["'][^>]*/?>"#, in: opfXML).first.flatMap({ $0.count > 1 ? $0[1] : nil }),
           let href = manifest[metaCoverID] {
            return opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
        }

        let coverItemPattern = #"<item\b[^>]*(?:properties=["'][^"']*cover-image[^"']*["']|id=["'][^"']*cover[^"']*["'])[^>]*\bhref=["']([^"']+)["'][^>]*/?>"#
        if let href = regexMatches(coverItemPattern, in: opfXML).first.flatMap({ $0.count > 1 ? $0[1] : nil }) {
            return opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
        }
        return nil
    }

    private static func epubTOCItems(opfXML: String, manifest: [String: String], opfDirectory: URL) -> [ReaderTOCItem] {
        let ncxHref = manifest["ncx"]
            ?? regexMatches(#"<item\b[^>]*\bmedia-type=["']application/x-dtbncx\+xml["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>"#, in: opfXML).first.flatMap { $0.count > 1 ? $0[1] : nil }
            ?? regexMatches(#"<item\b[^>]*\bhref=["']([^"']+\.ncx)["'][^>]*/?>"#, in: opfXML).first.flatMap { $0.count > 1 ? $0[1] : nil }
        if let ncxHref {
            let ncxURL = opfDirectory.appendingPathComponent(ncxHref.removingPercentEncoding ?? ncxHref)
            if let ncx = try? String(contentsOf: ncxURL, encoding: .utf8) {
                let items = epubNCXTOCItems(from: ncx)
                if !items.isEmpty { return items }
            }
        }

        let navHref = regexMatches(#"<item\b[^>]*\bproperties=["'][^"']*nav[^"']*["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>"#, in: opfXML).first.flatMap { $0.count > 1 ? $0[1] : nil }
        if let navHref {
            let navURL = opfDirectory.appendingPathComponent(navHref.removingPercentEncoding ?? navHref)
            if let nav = try? String(contentsOf: navURL, encoding: .utf8) {
                return epubHTMLNavItems(from: nav)
            }
        }
        return []
    }

    private static func epubNCXTOCItems(from xml: String) -> [ReaderTOCItem] {
        let navPoints = regexMatches(#"<navPoint\b[\s\S]*?</navPoint>"#, in: xml).compactMap(\.first)
        return navPoints.compactMap { navPoint in
            let title = regexMatches(#"<text\b[^>]*>([\s\S]*?)</text>"#, in: navPoint).first.flatMap { $0.count > 1 ? htmlToPlainText($0[1]) : nil } ?? ""
            let src = firstXMLAttribute("src", in: regexMatches(#"<content\b[^>]*/?>"#, in: navPoint).first?.first ?? "") ?? ""
            guard !title.isEmpty, !src.isEmpty else { return nil }
            let nestedCount = regexMatches(#"<navPoint\b"#, in: navPoint).count
            let level = max(0, nestedCount - 1)
            return ReaderTOCItem(title: title, href: normalizedEPUBTOCHref(src), level: min(level, 4))
        }
    }

    private static func epubHTMLNavItems(from html: String) -> [ReaderTOCItem] {
        regexMatches(#"<a\b[^>]*\bhref=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, in: html).compactMap { match in
            guard match.count > 2 else { return nil }
            let title = htmlToPlainText(match[2])
            guard !title.isEmpty else { return nil }
            return ReaderTOCItem(title: title, href: normalizedEPUBTOCHref(match[1]), level: 0)
        }
    }

    private static func normalizedEPUBTOCHref(_ href: String) -> String {
        if let fragment = href.split(separator: "#", maxSplits: 1).dropFirst().first, !fragment.isEmpty {
            return "#\(fragment)"
        }
        return href
    }

    private static func epubStylesheets(from opfXML: String, opfDirectory: URL) -> String {
        let pattern = #"<item\b[^>]*\bhref=["']([^"']+\.css)["'][^>]*\bmedia-type=["']text/css["'][^>]*/?>|<item\b[^>]*\bmedia-type=["']text/css["'][^>]*\bhref=["']([^"']+\.css)["'][^>]*/?>"#
        let styles = regexMatches(pattern, in: opfXML).compactMap { match -> String? in
            let href = match.dropFirst().first { !$0.isEmpty }
            guard let href else { return nil }
            let cssURL = opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let css = try? String(contentsOf: cssURL, encoding: .utf8) else { return nil }
            return prepareEPUBCSS(css, baseURL: cssURL.deletingLastPathComponent())
        }
        return styles.joined(separator: "\n\n")
    }

    private static func epubInlineStyles(from html: String, baseURL: URL) -> [String] {
        regexMatches(#"<style\b[^>]*>([\s\S]*?)</style>"#, in: html).compactMap { match in
            guard match.count > 1 else { return nil }
            return prepareEPUBCSS(match[1], baseURL: baseURL)
        }
    }

    private static func prepareEPUBCSS(_ css: String, baseURL: URL) -> String {
        let rewritten = rewriteCSSRelativeURLs(in: css, baseURL: baseURL)
        return rewriteEPUBBodySelectors(in: rewritten)
    }

    private static func rewriteEPUBBodySelectors(in css: String) -> String {
        var output = css
        output = output.replacingOccurrences(
            of: #"(?m)(^|[,{]\s*)body(?=\.|#|\[|:|\s|\{|,)"#,
            with: "$1.reader-section",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?m)(^|[,{]\s*)html(?=\.|#|\[|:|\s|\{|,)"#,
            with: "$1.reader-epub",
            options: .regularExpression
        )
        return output
    }

    private static func firstXMLAttribute(_ attribute: String, in xml: String) -> String? {
        let pattern = #"\#(attribute)=["']([^"']+)["']"#
        return regexMatches(pattern, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func docxParagraphs(from xml: String) -> [String] {
        let paragraphMatches = regexMatches(#"<w:p\b[\s\S]*?</w:p>"#, in: xml).compactMap(\.first)
        return paragraphMatches.map { paragraph in
            regexMatches(#"<w:t\b[^>]*>([\s\S]*?)</w:t>"#, in: paragraph)
                .compactMap { $0.count > 1 ? decodeXML($0[1]) : nil }
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
        var text = htmlToPlainText(html)
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
                parts.append(escapeHTML(decodeXML(text)))
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
            relationships[match[1]] = decodeXML(match[2])
        }
        return relationships
    }

    private static func docxTOCItems(from bodyHTML: String) -> [ReaderTOCItem] {
        var index = 0
        return regexMatches(#"<h([1-3])\b[^>]*>([\s\S]*?)</h\1>"#, in: bodyHTML).compactMap { match in
            guard match.count > 2, let headingLevel = Int(match[1]) else { return nil }
            let title = htmlToPlainText(match[2])
            guard !title.isEmpty else { return nil }
            index += 1
            return ReaderTOCItem(title: title, href: "#docx-heading-\(index)", level: headingLevel - 1)
        }
    }

    private static func rewriteRelativeLinks(in html: String, baseURL: URL) -> String {
        var output = html
        let base = baseURL.absoluteString
        output = output.replacingOccurrences(of: #"(?i)src=["'](?![a-z]+:|#|/)([^"']+)["']"#, with: "src=\"\(base)/$1\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)(xlink:href|href)=["'](?![a-z]+:|#|/)([^"']+\.(?:jpe?g|png|gif|webp|svg))["']"#, with: "$1=\"\(base)/$2\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)href=["'](?![a-z]+:|#)([^"']*#([^"']+))["']"#, with: "href=\"#$2\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)href=["'](?![a-z]+:|#)([^"']+)["']"#, with: "href=\"#\"", options: .regularExpression)
        return output
    }

    private static func rewriteCSSRelativeURLs(in css: String, baseURL: URL) -> String {
        let base = baseURL.absoluteString
        return css.replacingOccurrences(
            of: #"(?i)url\((['"]?)(?![a-z]+:|#|/)([^'")]+)\1\)"#,
            with: "url($1\(base)/$2$1)",
            options: .regularExpression
        )
    }

    private static func htmlBodyFragment(from html: String) -> HTMLBodyFragment {
        let pattern = #"<body\b([^>]*)>([\s\S]*?)</body>"#
        if let body = regexMatches(pattern, in: html).first, body.count > 2 {
            return HTMLBodyFragment(content: body[2], bodyClasses: bodyClasses(from: body[1]), bodyAttributes: body[1])
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

    private static func epubSectionAttributes(from bodyAttributes: String, bodyClasses: String) -> String {
        let classes = ["reader-section", bodyClasses].filter { !$0.isEmpty }.joined(separator: " ")
        var attributes = ["class=\"\(escapeHTML(classes))\""]
        for name in ["style", "lang", "xml:lang", "dir"] {
            if let value = firstXMLAttribute(name, in: bodyAttributes), !value.isEmpty {
                attributes.append("\(name)=\"\(escapeHTML(value))\"")
            }
        }
        return " " + attributes.joined(separator: " ")
    }

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
            .reader-section p, .reader-section li { line-height: 1.84; }
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

    private static func htmlToPlainText(_ html: String) -> String {
        decodeXML(html
            .replacingOccurrences(of: #"<script\b[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
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

    private static func decodeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
