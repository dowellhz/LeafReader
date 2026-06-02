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
        return MarkdownHTMLExporter.document(title: documentTitle, markdown: body)
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
