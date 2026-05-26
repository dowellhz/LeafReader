import Foundation

enum ReadingNoteExporter {
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
