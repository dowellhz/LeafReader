import Cocoa

enum ReadingNoteMarkdownSerializer {
    static func markdown(from attributed: NSAttributedString) -> String {
        let output = NSMutableString()
        (attributed.string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: attributed.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            let line = attributed.attributedSubstring(from: range)
            output.append(markdownLine(from: line))
            output.append("\n")
        }
        return (output as String).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func markdownLine(from attributed: NSAttributedString) -> String {
        if let imageMarkdown = imageMarkdownLine(from: attributed) {
            return imageMarkdown
        }
        let rawLine = attributed.string.trimmingCharacters(in: .newlines)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if let markdown = displayedListMarkdownLine(from: attributed, rawLine: rawLine) {
            return markdown
        }
        if let blockRaw = attributed.attribute(.leafMarkdownBlock, at: 0, effectiveRange: nil) as? String,
           let block = MarkdownRenderer.Block(rawValue: blockRaw) {
            switch block {
            case .heading1: return "# " + trimmed
            case .heading2: return "## " + trimmed
            case .heading3: return "### " + trimmed
            case .heading4: return "#### " + trimmed
            case .heading5: return "##### " + trimmed
            case .heading6: return "###### " + trimmed
            case .numberedList:
                return numberedMarkdownLine(from: attributed, rawLine: rawLine)
                    ?? "1. " + trimmed.replacingOccurrences(
                        of: #"^\d+\.\s+"#,
                        with: "",
                        options: .regularExpression
                    )
            case .bullet, .checklist, .paragraph:
                break
            }
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

    private static func displayedListMarkdownLine(from attributed: NSAttributedString, rawLine: String) -> String? {
        let prefixes = [
            (display: "• ", markdown: "- "),
            (display: "☐ ", markdown: "- [ ] "),
            (display: "☑ ", markdown: "- [x] ")
        ]
        for prefix in prefixes {
            if let markdown = prefixedMarkdownLine(
                from: attributed,
                rawLine: rawLine,
                displayPrefix: prefix.display,
                markdownPrefix: prefix.markdown
            ) {
                return markdown
            }
        }
        return nil
    }

    private static func prefixedMarkdownLine(
        from attributed: NSAttributedString,
        rawLine: String,
        displayPrefix: String,
        markdownPrefix: String
    ) -> String? {
        let nsLine = rawLine as NSString
        let leadingWhitespace = rawLine.prefix { $0 == " " || $0 == "\t" }.count
        let displayRange = NSRange(location: leadingWhitespace, length: (displayPrefix as NSString).length)
        guard displayRange.location + displayRange.length <= nsLine.length,
              nsLine.substring(with: displayRange) == displayPrefix else {
            return nil
        }
        let contentLocation = displayRange.location + displayRange.length
        let contentRange = NSRange(location: contentLocation, length: max(0, attributed.length - contentLocation))
        let content = inlineMarkdown(from: attributed, range: contentRange)
        return markdownPrefix + content
    }

    private static func numberedMarkdownLine(from attributed: NSAttributedString, rawLine: String) -> String? {
        let nsLine = rawLine as NSString
        guard let match = try? NSRegularExpression(pattern: #"^\s*\d+\.\s+"#).firstMatch(
            in: rawLine,
            range: NSRange(location: 0, length: nsLine.length)
        ) else {
            return nil
        }
        let contentLocation = match.range.location + match.range.length
        let contentRange = NSRange(location: contentLocation, length: max(0, attributed.length - contentLocation))
        let content = inlineMarkdown(from: attributed, range: contentRange)
        return "1. " + content
    }

    private static func imageMarkdownLine(from attributed: NSAttributedString) -> String? {
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

    private static func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        var output = ""
        attributed.enumerateAttributes(in: range) { attributes, subrange, _ in
            let text = attributed.attributedSubstring(from: subrange).string
            guard !text.isEmpty else { return }
            guard let font = attributes[.font] as? NSFont else {
                output += text
                return
            }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.monoSpace) {
                output += "`\(text)`"
            } else if traits.contains(.bold) {
                output += "**\(text)**"
            } else if traits.contains(.italic) {
                output += "*\(text)*"
            } else {
                output += text
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private static func isEntireRange(_ attributed: NSAttributedString, matching trait: NSFontDescriptor.SymbolicTraits) -> Bool {
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
