import Foundation

struct DOCXStreamingResult {
    let html: String
    let plainText: [String]
    let tocItems: [ReaderTOCItem]
}

enum DOCXMediaReferenceStyle {
    case absoluteFileURL
    case relativeToPreparedEntry
}

private enum DOCXXMLNamespace {
    static let wordProcessing = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let drawing = "http://schemas.openxmlformats.org/drawingml/2006/main"
}

private func docxAttribute(_ localName: String, in attributes: [String: String]) -> String? {
    if let exact = attributes[localName] {
        return exact
    }
    return attributes.first { key, _ in
        key.split(separator: ":").last.map(String.init) == localName
    }?.value
}

private func docxParseError(_ parser: XMLParser, document: String) -> Error {
    parser.parserError ?? NSError(domain: "LeafReader", code: -2, userInfo: [
        NSLocalizedDescriptionKey: AppText.localized("\(document) XML 无效。", "Invalid \(document) XML.")
    ])
}

private final class DOCXRelationshipXMLParser: NSObject, XMLParserDelegate {
    private let cancellationToken: DocumentLoadCancellationToken?
    private(set) var relationships: [String: String] = [:]

    init(cancellationToken: DocumentLoadCancellationToken?) {
        self.cancellationToken = cancellationToken
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if cancellationToken?.isCancelled == true {
            parser.abortParsing()
            return
        }
        guard elementName == "Relationship",
              let id = docxAttribute("Id", in: attributeDict),
              let target = docxAttribute("Target", in: attributeDict) else { return }
        relationships[id] = target
    }
}

private struct DOCXStreamingRun {
    var html: [String] = []
    var sourceText = ""
    var visibleText = ""
    var isBold = false
    var isItalic = false
    var isUnderlined = false
}

private struct DOCXStreamingParagraph {
    var html: [String] = []
    var sourceText = ""
    var visibleText = ""
    var style = ""
    var alignment: String?
    var isListItem = false
    var containsImage = false
}

private final class DOCXDocumentXMLParser: NSObject, XMLParserDelegate {
    private let directory: URL
    private let relationships: [String: String]
    private let mediaReferenceStyle: DOCXMediaReferenceStyle
    private let cancellationToken: DocumentLoadCancellationToken?

    private var output: [String] = ["<main class=\"docx-document\">"]
    private var plainText: [String] = []
    private var tocItems: [ReaderTOCItem] = []
    private var paragraph: DOCXStreamingParagraph?
    private var run: DOCXStreamingRun?
    private var hyperlinkHTML: [String]?
    private var hyperlinkTarget: String?
    private var textBuffer = ""
    private var isCollectingText = false
    private var isInsideBody = false
    private var tableDepth = 0
    private var rowDepth = 0
    private var cellDepth = 0
    private var flattenedRowDepths: Set<Int> = []
    private var flattenedCellDepths: Set<Int> = []
    private var flattenedTableDepths: Set<Int> = []
    private var renderedTableDepths: Set<Int> = []
    private var listOpen = false
    private var headingIndex = 0
    private var cancellationProbeCountdown = 256

    init(
        directory: URL,
        relationships: [String: String],
        mediaReferenceStyle: DOCXMediaReferenceStyle,
        cancellationToken: DocumentLoadCancellationToken?
    ) {
        self.directory = directory
        self.relationships = relationships
        self.mediaReferenceStyle = mediaReferenceStyle
        self.cancellationToken = cancellationToken
    }

    func result() -> DOCXStreamingResult {
        DOCXStreamingResult(html: output.joined(separator: "\n"), plainText: plainText, tocItems: tocItems)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if shouldAbortParsing() {
            parser.abortParsing()
            return
        }
        if namespaceURI == DOCXXMLNamespace.wordProcessing, elementName == "body" {
            isInsideBody = true
            return
        }
        guard isInsideBody else { return }

        if namespaceURI == DOCXXMLNamespace.drawing, elementName == "blip" {
            appendImage(relationshipID: docxAttribute("embed", in: attributeDict))
            return
        }
        guard namespaceURI == DOCXXMLNamespace.wordProcessing else { return }

        switch elementName {
        case "tbl":
            startTable()
        case "tr":
            rowDepth += 1
            if !flattenedRowDepths.contains(rowDepth) {
                output.append("<tr>")
            }
        case "tc":
            cellDepth += 1
            if !flattenedCellDepths.contains(cellDepth) {
                output.append("<td>")
            }
        case "p":
            paragraph = DOCXStreamingParagraph()
        case "pStyle":
            paragraph?.style = docxAttribute("val", in: attributeDict) ?? ""
        case "jc":
            paragraph?.alignment = docxAttribute("val", in: attributeDict)
        case "numPr":
            paragraph?.isListItem = true
        case "hyperlink":
            hyperlinkHTML = []
            hyperlinkTarget = docxAttribute("id", in: attributeDict).flatMap { relationships[$0] }
            paragraph?.visibleText.append(" ")
        case "r":
            run = DOCXStreamingRun()
        case "b":
            run?.isBold = true
        case "i":
            run?.isItalic = true
        case "u":
            run?.isUnderlined = true
        case "t":
            isCollectingText = true
            textBuffer.removeAll(keepingCapacity: true)
        case "tab":
            run?.html.append("&emsp;")
            run?.visibleText.append("\u{2003}")
        case "br":
            run?.html.append("<br>")
            run?.visibleText.append(" ")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if shouldAbortParsing() {
            parser.abortParsing()
            return
        }
        guard isCollectingText else { return }
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard namespaceURI == DOCXXMLNamespace.wordProcessing else { return }
        if elementName == "body" {
            closeListIfNeeded()
            output.append("</main>")
            isInsideBody = false
            return
        }
        guard isInsideBody else { return }

        switch elementName {
        case "t":
            isCollectingText = false
            run?.html.append(EPUBHTMLSanitizer.escapeHTML(textBuffer))
            run?.sourceText.append(textBuffer)
            run?.visibleText.append(textBuffer)
            textBuffer.removeAll(keepingCapacity: true)
        case "r":
            finishRun()
        case "hyperlink":
            finishHyperlink()
        case "p":
            finishParagraph()
        case "tc":
            if !flattenedCellDepths.contains(cellDepth) {
                output.append("</td>")
            }
            cellDepth = max(0, cellDepth - 1)
        case "tr":
            finishRow()
        case "tbl":
            finishTable()
        default:
            break
        }
    }

    private func startTable() {
        let nextTableDepth = tableDepth + 1
        if tableDepth == 0 {
            closeListIfNeeded()
            output.append("<table>")
            renderedTableDepths.insert(nextTableDepth)
        } else if flattenedTableDepths.contains(tableDepth) {
            output.append("<table>")
            renderedTableDepths.insert(nextTableDepth)
        } else if output.last == "<td>" {
            output.removeLast()
            flattenedCellDepths.insert(cellDepth)
            if output.last == "<tr>" {
                output.removeLast()
                flattenedRowDepths.insert(rowDepth)
            }
            renderedTableDepths.remove(tableDepth)
            flattenedTableDepths.insert(tableDepth)
            renderedTableDepths.insert(nextTableDepth)
        } else {
            output.append("<table>")
            renderedTableDepths.insert(nextTableDepth)
        }
        tableDepth = nextTableDepth
    }

    private func finishRow() {
        if !flattenedRowDepths.contains(rowDepth) {
            output.append("</tr>")
        } else {
            flattenedRowDepths.remove(rowDepth)
            flattenedCellDepths.remove(rowDepth)
        }
        rowDepth = max(0, rowDepth - 1)
    }

    private func finishTable() {
        if renderedTableDepths.contains(tableDepth) {
            output.append("</table>")
            renderedTableDepths.remove(tableDepth)
        }
        flattenedTableDepths.remove(tableDepth)
        tableDepth = max(0, tableDepth - 1)
    }

    private func finishRun() {
        guard let completedRun = run else { return }
        run = nil
        var html = completedRun.html.joined()
        if !html.isEmpty {
            if completedRun.isBold { html = "<strong>\(html)</strong>" }
            if completedRun.isItalic { html = "<em>\(html)</em>" }
            if completedRun.isUnderlined { html = "<u>\(html)</u>" }
        }
        if hyperlinkHTML != nil {
            hyperlinkHTML?.append(html)
        } else {
            paragraph?.html.append(html)
        }
        paragraph?.sourceText.append(completedRun.sourceText)
        if completedRun.isBold || completedRun.isItalic || completedRun.isUnderlined {
            paragraph?.visibleText.append(" ")
            paragraph?.visibleText.append(completedRun.visibleText)
            paragraph?.visibleText.append(" ")
        } else {
            paragraph?.visibleText.append(completedRun.visibleText)
        }
    }

    private func finishHyperlink() {
        guard let fragments = hyperlinkHTML else { return }
        hyperlinkHTML = nil
        let innerHTML = fragments.joined()
        if let target = hyperlinkTarget {
            paragraph?.html.append("<a href=\"\(EPUBHTMLSanitizer.escapeHTML(target))\">\(innerHTML)</a>")
        } else {
            paragraph?.html.append(innerHTML)
        }
        hyperlinkTarget = nil
        paragraph?.visibleText.append(" ")
    }

    private func finishParagraph() {
        guard let completed = paragraph else { return }
        paragraph = nil
        let sourceText = completed.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleText = collapsedVisibleText(completed.visibleText)
        var html = completed.html.joined()
        var isListItem = completed.isListItem || completed.style.localizedCaseInsensitiveContains("List")
        if visibleText.hasPrefix("- ") || visibleText.hasPrefix("• ") {
            html = String(html.dropFirst(2))
            isListItem = true
        }
        guard !visibleText.isEmpty || completed.containsImage else { return }
        if !sourceText.isEmpty {
            plainText.append(sourceText)
        }

        if cellDepth > 0 {
            output.append("<p>\(html)</p>")
            return
        }
        if isListItem {
            if !listOpen {
                output.append("<ul>")
                listOpen = true
            }
            output.append("<li>\(html)</li>")
            return
        }
        closeListIfNeeded()

        let classes = alignmentClasses(completed.alignment)
        let classAttribute = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        let tag = paragraphTag(style: completed.style)
        if tag.hasPrefix("h") {
            headingIndex += 1
            let href = "#docx-heading-\(headingIndex)"
            output.append("<\(tag) id=\"docx-heading-\(headingIndex)\"\(classAttribute)>\(html)</\(tag)>")
            if let level = Int(tag.dropFirst()), !visibleText.isEmpty {
                tocItems.append(ReaderTOCItem(title: visibleText, href: href, level: level - 1))
            }
        } else {
            output.append("<\(tag)\(classAttribute)>\(html)</\(tag)>")
        }
    }

    private func appendImage(relationshipID: String?) {
        guard let relationshipID,
              let source = WebDocumentLoader.docxMediaReference(
                for: relationshipID,
                directory: directory,
                relationships: relationships,
                style: mediaReferenceStyle
              ) else { return }
        run?.html.append("<img src=\"\(EPUBHTMLSanitizer.escapeHTML(source))\">")
        run?.visibleText.append(" ")
        paragraph?.containsImage = true
    }

    private func closeListIfNeeded() {
        guard listOpen else { return }
        output.append("</ul>")
        listOpen = false
    }

    private func paragraphTag(style: String) -> String {
        if style.localizedCaseInsensitiveContains("Heading1") || style.localizedCaseInsensitiveContains("Title") {
            return "h1"
        }
        if style.localizedCaseInsensitiveContains("Heading2") { return "h2" }
        if style.localizedCaseInsensitiveContains("Heading3") { return "h3" }
        return "p"
    }

    private func alignmentClasses(_ alignment: String?) -> [String] {
        switch alignment {
        case "center": return ["docx-align-center"]
        case "right": return ["docx-align-right"]
        case "both": return ["docx-align-justify"]
        default: return []
        }
    }

    private func collapsedVisibleText(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append(character)
            }
        }
        return result
    }

    private func shouldAbortParsing() -> Bool {
        cancellationProbeCountdown -= 1
        guard cancellationProbeCountdown <= 0 else { return false }
        cancellationProbeCountdown = 256
        return cancellationToken?.isCancelled == true
    }
}

extension WebDocumentLoader {
    static func docxStreamingRelationships(
        from url: URL,
        cancellationToken: DocumentLoadCancellationToken? = nil
    ) throws -> [String: String] {
        try cancellationToken?.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: AppText.localized("无法读取 DOCX 关系数据。", "Unable to read DOCX relationships.")
            ])
        }
        let delegate = DOCXRelationshipXMLParser(cancellationToken: cancellationToken)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            try cancellationToken?.checkCancellation()
            throw docxParseError(
                parser,
                document: AppText.localized("DOCX 关系数据", "DOCX relationships")
            )
        }
        return delegate.relationships
    }

    static func docxStreamingContent(
        from url: URL,
        directory: URL,
        relationships: [String: String],
        mediaReferenceStyle: DOCXMediaReferenceStyle = .absoluteFileURL,
        cancellationToken: DocumentLoadCancellationToken? = nil
    ) throws -> DOCXStreamingResult {
        try cancellationToken?.checkCancellation()
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: AppText.localized("无法读取 DOCX 文档 XML。", "Unable to read DOCX document XML.")
            ])
        }
        let delegate = DOCXDocumentXMLParser(
            directory: directory,
            relationships: relationships,
            mediaReferenceStyle: mediaReferenceStyle,
            cancellationToken: cancellationToken
        )
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            try cancellationToken?.checkCancellation()
            throw docxParseError(
                parser,
                document: AppText.localized("DOCX 文档", "DOCX document")
            )
        }
        return delegate.result()
    }
}
