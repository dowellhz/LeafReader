import Cocoa

struct ReadingNoteDocument: Equatable {
    var markdown: String

    static func imageMarkdown(url: URL, title: String? = nil) -> String {
        let displayTitle = sanitizedImageTitle(title ?? url.deletingPathExtension().lastPathComponent)
        return "![\(displayTitle)](\(url.absoluteString))"
    }

    func appendingAISection(title: String, body: String) -> ReadingNoteDocument {
        ReadingNoteDocument(markdown: markdownForAppendingSection(title: title) + body + "\n")
    }

    func appendingAISectionHeader(title: String) -> ReadingNoteDocument {
        ReadingNoteDocument(markdown: markdownForAppendingSection(title: title))
    }

    private func markdownForAppendingSection(title: String) -> String {
        let suffix = markdown.hasSuffix("\n") ? "" : "\n"
        return markdown + "\(suffix)\n### \(title)\n\n"
    }

    private static func sanitizedImageTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        return sanitized.isEmpty ? "image" : sanitized
    }
}

enum ReadingNoteDocumentCodec {
    static func editorProjection(
        from document: ReadingNoteDocument,
        fontSize: CGFloat,
        textColor: NSColor
    ) -> NSAttributedString {
        MarkdownRenderer.render(
            document.markdown,
            fontSize: fontSize,
            textColor: textColor
        )
    }

    static func document(fromEditorProjection attributed: NSAttributedString) -> ReadingNoteDocument {
        ReadingNoteDocument(markdown: ReadingNoteMarkdownSerializer.markdown(from: attributed))
    }
}
