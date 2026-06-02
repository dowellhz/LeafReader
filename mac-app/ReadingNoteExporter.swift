import Foundation

enum ReadingNoteExporter {
    enum Format: String, CaseIterable {
        case markdown
        case html
        case pdf

        var title: String {
            switch self {
            case .markdown:
                return "Markdown"
            case .html:
                return "HTML"
            case .pdf:
                return "PDF"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown:
                return "md"
            case .html:
                return "html"
            case .pdf:
                return "pdf"
            }
        }
    }

    enum Scope: String, CaseIterable {
        case all
        case favorites

        var title: String {
            switch self {
            case .all:
                return AppText.localized("全部笔记", "All notes")
            case .favorites:
                return AppText.localized("仅收藏笔记", "Favorite notes only")
            }
        }

        var fileNameSuffix: String {
            switch self {
            case .all:
                return "notes"
            case .favorites:
                return "favorite-notes"
            }
        }

        func filter(_ notes: [ReadingNote]) -> [ReadingNote] {
            switch self {
            case .all:
                return notes
            case .favorites:
                return notes.filter(\.isFavorite)
            }
        }
    }

    static func markdown(documentTitle: String, notes: [ReadingNote], exportedAt: Date = Date()) -> String {
        var lines: [String] = [
            "# \(documentTitle) - \(AppText.localized("阅读笔记", "Reading Notes"))",
            "",
            "- \(AppText.localized("导出时间", "Exported at"))：\(DateFormatter.localizedString(from: exportedAt, dateStyle: .medium, timeStyle: .short))",
            "- \(AppText.localized("笔记数", "Notes"))：\(notes.count)",
            ""
        ]
        for note in notes {
            lines.append("## \(locationText(note))")
            lines.append("")
            let body = note.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(body.isEmpty ? ReadingNoteMarkdown.blockquote(note.quote) : body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func html(documentTitle: String, notes: [ReadingNote], exportedAt: Date = Date()) -> String {
        let body = markdown(documentTitle: documentTitle, notes: notes, exportedAt: exportedAt)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>\(escapeHTML(documentTitle))</title>
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
        \(markdownBodyHTML(body))
        </body>
        </html>
        """
    }

    static func output(format: Format, documentTitle: String, notes: [ReadingNote], exportedAt: Date = Date()) -> String {
        switch format {
        case .markdown:
            return markdown(documentTitle: documentTitle, notes: notes, exportedAt: exportedAt)
        case .html:
            return html(documentTitle: documentTitle, notes: notes, exportedAt: exportedAt)
        case .pdf:
            return html(documentTitle: documentTitle, notes: notes, exportedAt: exportedAt)
        }
    }

    private static func locationText(_ note: ReadingNote) -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("第 \(first.pageIndex + 1) 页", "p. \(first.pageIndex + 1)")
        }
        return DateFormatter.localizedString(from: note.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    private static func markdownBodyHTML(_ markdown: String) -> String {
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
        escapeHTML(value)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum ReadingNoteMarkdown {
    static func defaultBody(quote: String) -> String {
        "\(blockquote(quote))\n\n## \(AppText.localized("笔记", "Notes"))\n\n"
    }

    static func blockquote(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }
}
