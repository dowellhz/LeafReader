import Cocoa

enum MarkdownInlineParser {
    static func applyInlineMarkdown(to attributed: NSMutableAttributedString, baseFontSize: CGFloat) {
        applyDelimitedStyle(to: attributed, delimiter: "**", font: NSFont.boldSystemFont(ofSize: baseFontSize))
        applyDelimitedStyle(to: attributed, delimiter: "__", font: NSFont.boldSystemFont(ofSize: baseFontSize))
        applyDelimitedStyle(
            to: attributed,
            delimiter: "*",
            font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)
        )
        applyDelimitedStyle(
            to: attributed,
            delimiter: "`",
            font: NSFont.monospacedSystemFont(ofSize: max(12, baseFontSize - 1), weight: .regular)
        )
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
}
