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
        if trimmed.hasPrefix("• ") {
            return "- " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☐ ") {
            return "- [ ] " + String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("☑ ") {
            return "- [x] " + String(trimmed.dropFirst(2))
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
            case .numberedList: return "1. " + trimmed.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
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
