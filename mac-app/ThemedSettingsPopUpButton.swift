import Cocoa

final class ThemedSettingsPopUpButton: NSPopUpButton {
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        backgroundColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let title = selectedItem?.title ?? self.title
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? AppFont.semibold(ofSize: 14),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = bounds.insetBy(dx: 14, dy: 0)
            .divided(atDistance: 34, from: .maxXEdge).remainder
        let titleSize = title.size(withAttributes: attrs)
        let drawRect = NSRect(
            x: textRect.minX,
            y: max(0, (bounds.height - titleSize.height) / 2),
            width: textRect.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: drawRect, withAttributes: attrs)

        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: arrowColor
        ]
        let arrow = "⌄"
        let arrowSize = arrow.size(withAttributes: arrowAttrs)
        arrow.draw(
            at: NSPoint(x: bounds.maxX - 24, y: max(0, (bounds.height - arrowSize.height) / 2)),
            withAttributes: arrowAttrs
        )
    }

    private var backgroundColor: NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.88, green: 0.83, blue: 0.68, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    private var borderColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    private var textColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    private var arrowColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.53, green: 0.37, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }
}
