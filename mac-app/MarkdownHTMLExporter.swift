import Foundation

enum MarkdownHTMLExporter {
    static func document(title: String, markdown: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>\(escapeHTML(title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; line-height: 1.62; max-width: 860px; margin: 40px auto; padding: 0 24px; color: #1f2328; }
            h1, h2, h3 { line-height: 1.25; }
            blockquote { margin: 16px 0; padding: 8px 16px; border-left: 4px solid #9bb7e8; background: #f6f8fb; color: #4b5563; }
            img { max-width: 100%; height: auto; border-radius: 6px; }
            code { background: #f2f4f7; padding: 0 4px; border-radius: 4px; }
            pre { background: #f2f4f7; padding: 12px; border-radius: 6px; overflow-x: auto; }
            li { margin: 4px 0; }
          </style>
        </head>
        <body>
        \(bodyHTML(markdown))
        </body>
        </html>
        """
    }

    static func bodyHTML(_ markdown: String) -> String {
        var html: [String] = []
        var listKind: String?

        func closeListIfNeeded() {
            if let currentListKind = listKind {
                html.append("</\(currentListKind)>")
                listKind = nil
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                closeListIfNeeded()
                continue
            }
            if let image = imageHTML(from: line) {
                closeListIfNeeded()
                html.append(image)
            } else if line.hasPrefix("### ") {
                closeListIfNeeded()
                html.append("<h3>\(inlineHTML(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                closeListIfNeeded()
                html.append("<h2>\(inlineHTML(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                closeListIfNeeded()
                html.append("<h1>\(inlineHTML(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("> ") {
                closeListIfNeeded()
                html.append("<blockquote>\(inlineHTML(String(line.dropFirst(2))))</blockquote>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if listKind != "ul" {
                    closeListIfNeeded()
                    listKind = "ul"
                    html.append("<ul>")
                }
                html.append("<li>\(inlineHTML(String(line.dropFirst(2))))</li>")
            } else if let numbered = numberedListItem(line) {
                if listKind != "ol" {
                    closeListIfNeeded()
                    listKind = "ol"
                    html.append("<ol>")
                }
                html.append("<li>\(inlineHTML(numbered))</li>")
            } else {
                closeListIfNeeded()
                html.append("<p>\(inlineHTML(line))</p>")
            }
        }
        closeListIfNeeded()
        return html.joined(separator: "\n")
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func numberedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let contentStart = line.index(after: dot)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return String(line[line.index(after: contentStart)...])
    }

    private static func imageHTML(from line: String) -> String? {
        guard line.hasPrefix("!["), let closeAlt = line.firstIndex(of: "]") else { return nil }
        let targetStart = line.index(closeAlt, offsetBy: 1)
        guard targetStart < line.endIndex, line[targetStart] == "(" else { return nil }
        guard line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeAlt])
        let urlStart = line.index(after: targetStart)
        let urlEnd = line.index(before: line.endIndex)
        let target = String(line[urlStart..<urlEnd])
        return "<p><img src=\"\(escapeHTMLAttribute(target))\" alt=\"\(escapeHTMLAttribute(alt))\"></p>"
    }

    private static func inlineHTML(_ value: String) -> String {
        var output = ""
        var index = value.startIndex
        var strongOpen = false
        var emphasisOpen = false
        var codeOpen = false

        func appendEscaped(_ character: Character) {
            output += escapeHTML(String(character))
        }

        while index < value.endIndex {
            if value[index] == "`" {
                output += codeOpen ? "</code>" : "<code>"
                codeOpen.toggle()
                index = value.index(after: index)
                continue
            }
            if !codeOpen,
               value[index...].hasPrefix("**") {
                output += strongOpen ? "</strong>" : "<strong>"
                strongOpen.toggle()
                index = value.index(index, offsetBy: 2)
                continue
            }
            if !codeOpen,
               value[index] == "*" {
                output += emphasisOpen ? "</em>" : "<em>"
                emphasisOpen.toggle()
                index = value.index(after: index)
                continue
            }
            appendEscaped(value[index])
            index = value.index(after: index)
        }

        if codeOpen { output += "</code>" }
        if emphasisOpen { output += "</em>" }
        if strongOpen { output += "</strong>" }
        return output
    }
}
