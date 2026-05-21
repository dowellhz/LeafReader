import Foundation

extension WebDocumentLoader {
    // MARK: - HTML Rewriting and Sanitizing

    static func rewriteRelativeLinks(
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

    static func rewriteHTMLAttributeURLs(
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

    static func rewriteEPUBInternalLinks(
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

    static func epubResourcePath(
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

    static var epubPathAllowedCharacters: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert("/")
        allowed.remove(charactersIn: "#?")
        return allowed
    }

    static func htmlBodyFragment(from html: String) -> HTMLBodyFragment {
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

    static func bodyClasses(from attributes: String) -> String {
        let pattern = #"\bclass=["']([^"']+)["']"#
        return regexMatches(pattern, in: attributes).first.flatMap { $0.count > 1 ? $0[1] : nil } ?? ""
    }

    static func epubSectionAttributes(
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

    static func isEPUBCoverSection(href: String, fragment: HTMLBodyFragment) -> Bool {
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

    static func hrefWithoutFragment(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
    }

    // MARK: - Page Rendering

    enum PageProfile {
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
            .reader-section,
            .reader-section * {
              -webkit-user-select: text !important;
              user-select: text !important;
            }
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

    static func pageHTML(title: String, body: String, documentStyles: String = "", profile: PageProfile = .epub) -> String {
        """
        <!doctype html>
        <html class="\(profile.htmlClass)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html { background: #f6f8fb; }
            :root { --reader-zoom: 1; }
            body { box-sizing: border-box; width: min(820px, calc(100vw - 144px)); min-height: 100vh; margin: 0 auto; padding: 56px 72px 96px; color: #191b20; background: white; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; font-size: calc(18px * var(--reader-zoom)); line-height: 1.72; overflow-wrap: break-word; -webkit-user-select: text; user-select: text; }
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

    static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
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

    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
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

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }}
