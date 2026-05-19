import Foundation

struct VocabularyExporter {
    struct Record {
        let word: String
        let answer: String
        let location: String
        let context: String
        let source: String
        let createdAt: Date
    }

    struct MarkdownLabels {
        let titleSuffix: String
        let exportedAt: String
        let wordCount: String
        let location: String
        let context: String
    }

    static func exportableRecords(_ records: [Record]) -> [Record] {
        records.filter { hasTrimmedText($0.answer) }
    }

    static func markdown(
        records: [Record],
        documentTitle: String,
        labels: MarkdownLabels,
        exportedAt: Date = Date(),
        answerBody: (Record) -> String
    ) -> String {
        var lines: [String] = [
            "# \(documentTitle) \(labels.titleSuffix)",
            "",
            "- \(labels.exportedAt)：\(DateFormatter.localizedString(from: exportedAt, dateStyle: .medium, timeStyle: .short))",
            "- \(labels.wordCount)：\(records.count)",
            ""
        ]
        for record in records {
            lines.append("## \(record.word)")
            lines.append("")
            lines.append("- \(labels.location)：\(record.location)")
            if hasTrimmedText(record.context) {
                lines.append("- \(labels.context)：\(record.context)")
            }
            lines.append("")
            lines.append(answerBody(record))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func csv(records: [Record], answerBody: (Record) -> String) -> String {
        var rows = ["Front,Back,Page,Context,Source,Created At"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([
                record.word,
                answerBody(record),
                record.location,
                record.context,
                record.source,
                formatter.string(from: record.createdAt)
            ].map(csvEscaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nonEmptyText(_ text: String?) -> String? {
        guard let value = text.map(trimmed), !value.isEmpty else { return nil }
        return value
    }

    static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }
}
