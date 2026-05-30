import Cocoa

extension NSAttributedString.Key {
    static let leafMarkdownBlock = NSAttributedString.Key("LeafReaderMarkdownBlock")
}

enum MarkdownRenderer {
    static func render(
        _ text: String,
        fontSize: CGFloat = 15,
        textColor: NSColor,
        scalesHeadings: Bool = true
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let blocks = MarkdownBlockParser.parse(text, baseFontSize: fontSize, scalesHeadings: scalesHeadings)

        for block in blocks {
            if block.rawLine.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            if let image = imageLine(block.rawLine, textColor: textColor) {
                output.append(image)
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            let baseFont = block.isHeading || block.isBoldLine
                ? NSFont.boldSystemFont(ofSize: block.fontSize)
                : NSFont.systemFont(ofSize: block.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor,
                .leafMarkdownBlock: block.type.rawValue,
                .paragraphStyle: paragraphStyle(
                    spacing: block.isHeading ? 6 : 4,
                    headIndent: block.isBullet ? 18 : 0,
                    firstLineHeadIndent: 0
                )
            ]
            let rendered = NSMutableAttributedString(string: block.display + "\n", attributes: attrs)
            MarkdownInlineParser.applyInlineMarkdown(to: rendered, baseFontSize: block.fontSize)
            output.append(rendered)
        }

        return output
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
        let url = imageURL(fromMarkdownTarget: target)
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

    private static func imageURL(fromMarkdownTarget target: String) -> URL {
        if let url = URL(string: target), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: target)
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

    private static func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
        return style
    }
}
