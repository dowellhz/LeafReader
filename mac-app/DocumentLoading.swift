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

        var sections: [String] = []
        var plainTextParts: [String] = []
        for id in spineIDs {
            guard let href = manifest[id] else { continue }
            let chapterURL = opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let chapter = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }
            sections.append(rewriteRelativeLinks(in: htmlBodyContent(from: chapter), baseURL: chapterURL.deletingLastPathComponent()))
            plainTextParts.append(htmlToPlainText(chapter))
        }

        let body = sections.isEmpty ? "<p>Unable to read EPUB content.</p>" : sections.joined(separator: "\n<hr>\n")
        return WebReadableDocument(
            html: pageHTML(title: url.deletingPathExtension().lastPathComponent, body: body),
            baseURL: opfDirectory,
            plainText: plainTextParts.joined(separator: "\n\n"),
            coverImageURL: epubCoverImageURL(opfXML: opfXML, manifest: manifest, opfDirectory: opfDirectory)
        )
    }

    private static func loadDOCX(url: URL) throws -> WebReadableDocument {
        let directory = try unzip(url: url)
        let documentURL = directory.appendingPathComponent("word/document.xml")
        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        let body = docxParagraphs(from: xml)
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined(separator: "\n")
        let title = url.deletingPathExtension().lastPathComponent
        let plainText = docxParagraphs(from: xml).joined(separator: "\n\n")
        return WebReadableDocument(html: pageHTML(title: title, body: body.isEmpty ? "<p>Unable to read DOCX content.</p>" : body), baseURL: directory, plainText: plainText, coverImageURL: nil)
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

    private static func rewriteRelativeLinks(in html: String, baseURL: URL) -> String {
        var output = html
        let base = baseURL.absoluteString
        output = output.replacingOccurrences(of: #"(?i)src=["'](?![a-z]+:|#|/)([^"']+)["']"#, with: "src=\"\(base)/$1\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)(xlink:href|href)=["'](?![a-z]+:|#|/)([^"']+\.(?:jpe?g|png|gif|webp|svg))["']"#, with: "$1=\"\(base)/$2\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)href=["'](?![a-z]+:|#)([^"']*#([^"']+))["']"#, with: "href=\"#$2\"", options: .regularExpression)
        output = output.replacingOccurrences(of: #"(?i)href=["'](?![a-z]+:|#)([^"']+)["']"#, with: "href=\"#\"", options: .regularExpression)
        return output
    }

    private static func htmlBodyContent(from html: String) -> String {
        let pattern = #"<body\b[^>]*>([\s\S]*?)</body>"#
        if let body = regexMatches(pattern, in: html).first, body.count > 1 {
            return body[1]
        }
        return html
            .replacingOccurrences(of: #"(?i)<!doctype[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?html[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<head\b[\s\S]*?</head>"#, with: "", options: .regularExpression)
    }

    private static func pageHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html { background: #f6f8fb; }
            :root { --reader-zoom: 1; }
            body { box-sizing: border-box; width: min(820px, calc(100vw - 96px)); min-height: 100vh; margin: 0 auto; padding: 56px 64px 96px; color: #191b20; background: white; font: calc(18px * var(--reader-zoom))/1.72 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; overflow-wrap: break-word; }
            h1, h2, h3 { line-height: 1.28; margin: 1.5em 0 .5em; }
            p { margin: 0 0 1em; }
            img { display: block; max-width: min(100%, 680px); height: auto; margin: 1.4em auto; object-fit: contain; }
            svg { display: block; max-width: min(100%, 420px); height: auto; margin: 1.4em auto; }
            hr { border: 0; border-top: 1px solid #e5e7eb; margin: 2.4em 0; }
            a { color: #1f5fbf; text-decoration-thickness: .08em; text-underline-offset: .16em; }
            ::selection { background: rgba(255, 221, 87, .62); }
            @media (max-width: 760px) { body { width: 100vw; padding: 36px 28px 72px; } }
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
