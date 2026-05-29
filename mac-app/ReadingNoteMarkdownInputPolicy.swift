import Foundation

enum ReadingNoteMarkdownInputPolicy {
    private static let blockPatterns = [
        #"^#{1,6}\s+\S"#,
        #"^[-*]\s+\S"#,
        #"^\d+\.\s+\S"#,
        #"^- \[[ xX]\]\s+\S"#
    ]

    private static let inlinePatterns = [
        #"\*\*[^*\n]+?\*\*"#,
        #"__[^_\n]+?__"#,
        #"(^|[^*])\*[^*\n]+?\*([^*]|$)"#,
        #"`[^`\n]+?`"#
    ]

    static func shouldRenderCompletedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return (blockPatterns + inlinePatterns).contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func shouldRenderPastedText(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { shouldRenderCompletedLine($0) }
    }
}
