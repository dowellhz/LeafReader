import Cocoa

extension NSAttributedString.Key {
    static let leafMarkdownBlock = NSAttributedString.Key("LeafReaderMarkdownBlock")
}

enum MarkdownRenderer {
    static func render(_ text: String, fontSize: CGFloat = 15, textColor: NSColor) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let nextNonEmptyLines = nextNonEmptyLineLookup(for: trimmedLines)
        var hasContent = false
        var previousLineWasBlank = false
        var previousNonEmptyLine: String?

        for (index, line) in trimmedLines.enumerated() {
            if line.isEmpty {
                if shouldSkipCompactExplanationBlankLine(previousLine: previousNonEmptyLine, nextLine: nextNonEmptyLines[index]) {
                    continue
                }
                guard hasContent, !previousLineWasBlank else { continue }
                output.append(NSAttributedString(string: "\n"))
                previousLineWasBlank = true
                continue
            }
            hasContent = true
            previousLineWasBlank = false
            previousNonEmptyLine = line

            if let image = imageLine(line, textColor: textColor) {
                output.append(image)
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            let parsed = markdownLine(line, baseFontSize: fontSize)
            let baseFont = parsed.isHeading || parsed.isBoldLine
                ? NSFont.boldSystemFont(ofSize: parsed.fontSize)
                : NSFont.systemFont(ofSize: parsed.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor,
                .leafMarkdownBlock: parsed.block.rawValue,
                .paragraphStyle: paragraphStyle(
                    spacing: parsed.isHeading ? 6 : 4,
                    headIndent: parsed.isBullet ? 18 : 0,
                    firstLineHeadIndent: 0
                )
            ]
            let rendered = NSMutableAttributedString(string: parsed.display + "\n", attributes: attrs)
            applyInlineMarkdown(to: rendered, baseFontSize: parsed.fontSize)
            output.append(rendered)
        }

        return output
    }

    private static func nextNonEmptyLineLookup(for lines: [String]) -> [String?] {
        var lookup = Array<String?>(repeating: nil, count: lines.count)
        var nextLine: String?
        for index in lines.indices.reversed() {
            lookup[index] = nextLine
            if !lines[index].isEmpty {
                nextLine = lines[index]
            }
        }
        return lookup
    }

    private static func shouldSkipCompactExplanationBlankLine(previousLine: String?, nextLine: String?) -> Bool {
        guard let previousLine, let nextLine else {
            return false
        }
        if isStandaloneBoldLine(previousLine) && isStandaloneBoldLine(nextLine) {
            return true
        }
        return isTranslationHeadingLine(nextLine)
    }

    private static func isStandaloneBoldLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4)
            || (trimmed.hasPrefix("__") && trimmed.hasSuffix("__") && trimmed.count > 4)
    }

    private static func isTranslationHeadingLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*:：: "))
            .lowercased()
        return normalized == "翻译"
            || normalized == "译文"
            || normalized == "translation"
            || normalized == "explanation"
    }

    private static func isReadingNoteSectionHeading(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*_：: "))
            .lowercased()
        return normalized == "笔记"
            || normalized == "解析"
            || normalized == "翻译"
            || normalized == "总结"
            || normalized == "整理"
            || normalized == "润色"
            || normalized == "notes"
            || normalized == "note"
            || normalized == "explain"
            || normalized == "explanation"
            || normalized == "translate"
            || normalized == "translation"
            || normalized == "summary"
            || normalized == "summarize"
            || normalized == "organize"
            || normalized == "polish"
    }

    enum Block: String {
        case paragraph
        case heading1
        case heading2
        case heading3
        case heading4
        case heading5
        case heading6
        case bullet
        case numberedList
        case checklist
    }

    private static func markdownLine(_ line: String, baseFontSize: CGFloat) -> (display: String, isHeading: Bool, isBoldLine: Bool, isBullet: Bool, fontSize: CGFloat, block: Block) {
        var display = line
        var isHeading = false
        var fontSize = baseFontSize
        var block: Block = .paragraph

        if let range = display.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            let marker = String(display[range]).trimmingCharacters(in: .whitespaces)
            display.removeSubrange(range)
            isHeading = true
            switch marker.count {
            case 1:
                fontSize = baseFontSize + 3
                block = .heading1
            case 2:
                fontSize = baseFontSize + 1
                block = .heading2
            case 3:
                block = .heading3
            case 4:
                block = .heading4
            case 5:
                block = .heading5
            default:
                block = .heading6
            }
        } else if display.hasPrefix("【"), display.contains("】") {
            isHeading = true
            block = .heading3
        } else if isReadingNoteSectionHeading(display) {
            isHeading = true
            block = .heading3
        }

        let isBullet = display.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil
            || display.range(of: #"^- \[[ xX]\]\s+"#, options: .regularExpression) != nil
            || display.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        if display.range(of: #"^- \[[ xX]\]\s+"#, options: .regularExpression) != nil {
            block = .checklist
        } else if display.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            block = .numberedList
        } else if display.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil {
            block = .bullet
        }
        display = display
            .replacingOccurrences(of: #"^- \[ \]\s+"#, with: "☐ ", options: .regularExpression)
            .replacingOccurrences(of: #"^- \[[xX]\]\s+"#, with: "☑ ", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
        display = display
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "• ", options: .regularExpression)

        let trimmed = display.trimmingCharacters(in: .whitespaces)
        let isBoldLine = isStandaloneBoldLine(trimmed)

        return (display, isHeading, isBoldLine, isBullet, fontSize, block)
    }

    private static func imageLine(_ line: String, textColor: NSColor) -> NSAttributedString? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#) else { return nil }
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges == 3 else {
            return nil
        }
        let title = nsLine.substring(with: match.range(at: 1))
        let target = nsLine.substring(with: match.range(at: 2))
        let url = URL(string: target) ?? URL(fileURLWithPath: target)
        guard let image = NSImage(contentsOf: url) else {
            return NSAttributedString(
                string: title.isEmpty ? target : title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: textColor.withAlphaComponent(0.72)
                ]
            )
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = scaledImageBounds(for: image)
        let rendered = NSMutableAttributedString(attachment: attachment)
        rendered.addAttribute(.link, value: url.absoluteString, range: NSRange(location: 0, length: rendered.length))
        return rendered
    }

    private static func scaledImageBounds(for image: NSImage) -> NSRect {
        let maxWidth: CGFloat = 360
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: -4, width: 180, height: 120)
        }
        let scale = min(1, maxWidth / size.width)
        return NSRect(x: 0, y: -4, width: size.width * scale, height: size.height * scale)
    }

    private static func applyInlineMarkdown(to attributed: NSMutableAttributedString, baseFontSize: CGFloat) {
        applyDelimitedStyle(to: attributed, delimiter: "**", font: NSFont.boldSystemFont(ofSize: baseFontSize))
        applyDelimitedStyle(to: attributed, delimiter: "__", font: NSFont.boldSystemFont(ofSize: baseFontSize))
        applyDelimitedStyle(to: attributed, delimiter: "*", font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask))
        applyDelimitedStyle(to: attributed, delimiter: "`", font: NSFont.monospacedSystemFont(ofSize: max(12, baseFontSize - 1), weight: .regular))
    }

    private static func applyDelimitedStyle(to attributed: NSMutableAttributedString, delimiter: String, font: NSFont) {
        while true {
            let full = attributed.string as NSString
            let start = full.range(of: delimiter)
            guard start.location != NSNotFound else { return }
            let searchStart = start.location + start.length
            let searchRange = NSRange(location: searchStart, length: full.length - searchStart)
            let end = full.range(of: delimiter, options: [], range: searchRange)
            guard end.location != NSNotFound else { return }

            attributed.deleteCharacters(in: end)
            attributed.deleteCharacters(in: start)
            let styledRange = NSRange(location: start.location, length: end.location - searchStart)
            if styledRange.length > 0 {
                attributed.addAttribute(.font, value: font, range: styledRange)
            }
        }
    }

    private static func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
        return style
    }
}
