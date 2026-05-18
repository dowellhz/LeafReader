import Cocoa

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

            let parsed = markdownLine(line, baseFontSize: fontSize)
            let baseFont = parsed.isHeading || parsed.isBoldLine
                ? NSFont.boldSystemFont(ofSize: parsed.fontSize)
                : NSFont.systemFont(ofSize: parsed.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor,
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

    private static func markdownLine(_ line: String, baseFontSize: CGFloat) -> (display: String, isHeading: Bool, isBoldLine: Bool, isBullet: Bool, fontSize: CGFloat) {
        var display = line
        var isHeading = false
        var fontSize = baseFontSize

        if let range = display.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            let marker = String(display[range]).trimmingCharacters(in: .whitespaces)
            display.removeSubrange(range)
            isHeading = true
            fontSize = marker.count <= 1 ? baseFontSize + 3 : (marker.count == 2 ? baseFontSize + 1 : baseFontSize)
        } else if display.hasPrefix("【"), display.contains("】") {
            isHeading = true
        }

        let isBullet = display.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil
            || display.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        display = display
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "• ", options: .regularExpression)

        let trimmed = display.trimmingCharacters(in: .whitespaces)
        let isBoldLine = isStandaloneBoldLine(trimmed)

        return (display, isHeading, isBoldLine, isBullet, fontSize)
    }

    private static func applyInlineMarkdown(to attributed: NSMutableAttributedString, baseFontSize: CGFloat) {
        applyDelimitedStyle(to: attributed, delimiter: "**", font: NSFont.boldSystemFont(ofSize: baseFontSize))
        applyDelimitedStyle(to: attributed, delimiter: "__", font: NSFont.boldSystemFont(ofSize: baseFontSize))
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
