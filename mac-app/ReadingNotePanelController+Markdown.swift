import Cocoa

extension ReadingNotePanelController {
    func renderMarkdownIntoEditor(_ markdown: String) {
        let rendered = MarkdownRenderer.render(
            markdown,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        textView.textStorage?.setAttributedString(rendered)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        ]
    }

    func markdownFromEditor() -> String {
        let attributed = textView.attributedString()
        let output = NSMutableString()
        (attributed.string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: attributed.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            let line = attributed.attributedSubstring(from: range)
            output.append(self.markdownLine(from: line))
            output.append("\n")
        }
        return (output as String).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func markdownLine(from attributed: NSAttributedString) -> String {
        if let imageMarkdown = imageMarkdownLine(from: attributed) {
            return imageMarkdown
        }
        let rawLine = attributed.string.trimmingCharacters(in: .newlines)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("• ") {
            return "- " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☐ ") {
            return "- [ ] " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☑ ") {
            return "- [x] " + String(trimmed.dropFirst(2))
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        if let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            if font.pointSize >= 18 {
                return "# " + trimmed
            }
            if font.fontDescriptor.symbolicTraits.contains(.bold), isEntireRange(attributed, matching: .bold) {
                return "**" + trimmed + "**"
            }
        }
        return inlineMarkdown(from: attributed, range: fullRange)
    }

    private func imageMarkdownLine(from attributed: NSAttributedString) -> String? {
        var value: String?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, stop in
            guard attributes[.attachment] is NSTextAttachment else { return }
            let urlString = (attributes[.link] as? String) ?? (attributes[.link] as? URL)?.absoluteString
            guard let urlString,
                  let url = URL(string: urlString) else { return }
            let name = url.deletingPathExtension().lastPathComponent
            value = "![\(name)](\(url.path))"
            stop.pointee = true
        }
        return value
    }

    private func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        var output = ""
        attributed.enumerateAttributes(in: range) { attributes, subrange, _ in
            let text = attributed.attributedSubstring(from: subrange).string
            guard !text.isEmpty else { return }
            guard let font = attributes[.font] as? NSFont else {
                output += text
                return
            }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                output += "**\(text)**"
            } else if traits.contains(.italic) {
                output += "*\(text)*"
            } else {
                output += text
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private func isEntireRange(_ attributed: NSAttributedString, matching trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        var matches = true
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let font = value as? NSFont,
                  font.fontDescriptor.symbolicTraits.contains(trait) else {
                matches = false
                stop.pointee = true
                return
            }
        }
        return matches
    }
}
