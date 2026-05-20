import Foundation

struct DOCXParagraph {
    let html: String
    let text: String
    let tag: String
    let classes: [String]
    let isListItem: Bool
}

extension WebDocumentLoader {
    // MARK: - DOCX Loading

    static func loadDOCX(url: URL) throws -> WebReadableDocument {
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
            tocItems: docxTOCItems(from: body),
            diagnostics: []
        )
    }

    // MARK: - DOCX Rendering

    static func docxParagraphs(from xml: String) -> [String] {
        let paragraphMatches = regexMatches(#"<w:p\b[\s\S]*?</w:p>"#, in: xml).compactMap(\.first)
        return paragraphMatches.map { paragraph in
            regexMatches(#"<w:t\b[^>]*>([\s\S]*?)</w:t>"#, in: paragraph)
                .compactMap { $0.count > 1 ? EPUBHTMLSanitizer.decodeEntities($0[1]) : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    static let docxReaderStyles = """
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

    static func docxBodyHTML(from xml: String, directory: URL, relationships: [String: String]) -> String {
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

    static func docxTopLevelBlocks(from body: String) -> [String] {
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

    static func docxTableHTML(from table: String, directory: URL, relationships: [String: String]) -> String {
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

    static func docxParagraphHTML(from paragraph: String, directory: URL, relationships: [String: String]) -> DOCXParagraph {
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

    static func docxInlineHTML(from runOrHyperlink: String, directory: URL, relationships: [String: String]) -> String {
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

    static func docxMediaURL(for relationshipID: String, directory: URL, relationships: [String: String]) -> URL? {
        guard let target = relationships[relationshipID] else { return nil }
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            return URL(string: target)
        }
        return directory.appendingPathComponent("word").appendingPathComponent(target)
    }

    static func docxRelationships(from url: URL) -> [String: String] {
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var relationships: [String: String] = [:]
        let pattern = #"<Relationship\b[^>]*\bId=["']([^"']+)["'][^>]*\bTarget=["']([^"']+)["'][^>]*/?>"#
        for match in regexMatches(pattern, in: xml) where match.count > 2 {
            relationships[match[1]] = EPUBHTMLSanitizer.decodeEntities(match[2])
        }
        return relationships
    }

    static func docxTOCItems(from bodyHTML: String) -> [ReaderTOCItem] {
        var index = 0
        return regexMatches(#"<h([1-3])\b[^>]*>([\s\S]*?)</h\1>"#, in: bodyHTML).compactMap { match in
            guard match.count > 2, let headingLevel = Int(match[1]) else { return nil }
            let title = EPUBHTMLSanitizer.plainText(from: match[2])
            guard !title.isEmpty else { return nil }
            index += 1
            return ReaderTOCItem(title: title, href: "#docx-heading-\(index)", level: headingLevel - 1)
        }
    }

}
