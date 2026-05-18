import Foundation

enum EPUBHTMLSanitizer {
    private static let removableBlockPatterns = [
        #"(?i)<script\b[\s\S]*?</script>"#,
        #"(?i)<style\b[\s\S]*?</style>"#,
        #"(?i)<(?:iframe|object|embed)\b[\s\S]*?</(?:iframe|object|embed)>"#,
        #"(?i)<(?:iframe|object|embed)\b[^>]*?/?>"#
    ]

    private static let eventAttributePatterns = [
        #"(?i)\s+on[a-z0-9:-]+\s*=\s*"[^"]*""#,
        #"(?i)\s+on[a-z0-9:-]+\s*=\s*'[^']*'"#,
        #"(?i)\s+on[a-z0-9:-]+\s*=\s*[^\s>]+"#
    ]

    private static let javascriptURLPatterns = [
        #"(?i)\s+(?:href|src|xlink:href)\s*=\s*"javascript:[^"]*""#,
        #"(?i)\s+(?:href|src|xlink:href)\s*=\s*'javascript:[^']*'"#,
        #"(?i)\s+(?:href|src|xlink:href)\s*=\s*javascript:[^\s>]+"#
    ]

    private static let namedEntities: [(entity: String, replacement: String)] = [
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&nbsp;", "\u{00A0}"),
        ("&ensp;", "\u{2002}"),
        ("&emsp;", "\u{2003}"),
        ("&ndash;", "\u{2013}"),
        ("&mdash;", "\u{2014}"),
        ("&lsquo;", "\u{2018}"),
        ("&rsquo;", "\u{2019}"),
        ("&ldquo;", "\u{201C}"),
        ("&rdquo;", "\u{201D}"),
        ("&hellip;", "\u{2026}"),
        ("&amp;", "&")
    ]

    static func sanitizeContent(_ html: String) -> String {
        var output = html
        for pattern in removableBlockPatterns + eventAttributePatterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        for pattern in javascriptURLPatterns {
            output = output.replacingOccurrences(of: pattern, with: " href=\"#\"", options: .regularExpression)
        }
        output = output.replacingOccurrences(
            of: #"(?i)<([a-z0-9:-]+)([^>]*)\bid=["']sbo-rt-content["']([^>]*)>"#,
            with: "<$1$2$3 data-reader-original-id=\"sbo-rt-content\" class=\"sbo-rt-content\">",
            options: .regularExpression
        )
        return addLazyLoadingToImages(in: output)
    }

    static func addLazyLoadingToImages(in html: String) -> String {
        guard let regex = cachedRegex(#"(?i)<img\b[^>]*>"#) else { return html }
        let nsHTML = html as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            output += nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let tag = nsHTML.substring(with: match.range)
            if tag.range(of: #"(?i)\sloading\s*="#, options: .regularExpression) != nil {
                output += tag
            } else if tag.hasSuffix("/>") {
                let insertIndex = tag.index(tag.endIndex, offsetBy: -2)
                output += String(tag[..<insertIndex]) + #" loading="lazy"/>"#
            } else {
                let insertIndex = tag.index(before: tag.endIndex)
                output += String(tag[..<insertIndex]) + #" loading="lazy">"#
            }
            cursor = match.range.location + match.range.length
        }
        output += nsHTML.substring(from: cursor)
        return output
    }

    static func plainText(from html: String) -> String {
        decodeEntities(html
            .replacingOccurrences(of: #"<script\b[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var output = decodeNumericEntities(in: text)
        for entity in namedEntities {
            output = output.replacingOccurrences(of: entity.entity, with: entity.replacement)
        }
        return output
    }

    private static func decodeNumericEntities(in text: String) -> String {
        guard let regex = cachedRegex(#"&#(x[0-9a-fA-F]+|[0-9]+);"#) else { return text }
        let nsText = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let value = nsText.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if value.lowercased().hasPrefix("x") {
                scalarValue = UInt32(value.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(value, radix: 10)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                output += String(Character(scalar))
            } else {
                output += nsText.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        output += nsText.substring(from: cursor)
        return output
    }

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
