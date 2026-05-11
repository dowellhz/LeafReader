import Cocoa

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class GradientButton: NSButton {
    var previewText = "" {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet {
            layer?.shadowOpacity = isEnabled ? 0.24 : 0
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 18, yRadius: 18)

        if isEnabled {
            let gradient = NSGradient(colors: [
                NSColor(red: 0.45, green: 0.18, blue: 0.96, alpha: 1),
                NSColor(red: 0.21, green: 0.50, blue: 0.98, alpha: 1)
            ])
            gradient?.draw(in: path, angle: 0)
            NSColor(red: 0.25, green: 0.33, blue: 0.92, alpha: 0.24).setStroke()
        } else {
            NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).setFill()
            path.fill()
            NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1).setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        let title = AppText.askAI
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: isEnabled ? NSColor.white : NSColor(red: 0.70, green: 0.71, blue: 0.76, alpha: 1)
        ]
        let previewAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]

        let leftPadding: CGFloat = 18
        let gap: CGFloat = 10
        let rightPadding: CGFloat = 16
        let titleSize = title.size(withAttributes: titleAttrs)
        let midY = (bounds.height - titleSize.height) / 2 + 1
        title.draw(at: NSPoint(x: leftPadding, y: midY), withAttributes: titleAttrs)

        let preview = singleLinePreview(previewText)
        guard !preview.isEmpty else { return }

        let previewX = leftPadding + titleSize.width + gap
        let previewWidth = max(0, bounds.width - previewX - rightPadding)
        guard previewWidth > 12 else { return }
        let previewRect = NSRect(
            x: previewX,
            y: (bounds.height - 17) / 2,
            width: previewWidth,
            height: 17
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.maximumLineHeight = 17

        var attrs = previewAttrs
        attrs[.paragraphStyle] = paragraph
        (preview as NSString).draw(in: previewRect, withAttributes: attrs)
    }

    private func singleLinePreview(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SideHandleButton: NSButton {
    static let handleWidth: CGFloat = 14
    static let handleHeight: CGFloat = 50

    var collapsedStyle = true {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        let fill = collapsedStyle
            ? NSColor(red: isHighlighted ? 0.92 : 0.98, green: isHighlighted ? 0.16 : 0.24, blue: isHighlighted ? 0.17 : 0.24, alpha: 1)
            : NSColor(red: 0.22, green: 0.50, blue: 0.98, alpha: 1)
        fill.setFill()
        path.fill()

        let symbol = collapsedStyle ? "‹" : "›"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let size = symbol.size(withAttributes: attrs)
        symbol.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 + 1), withAttributes: attrs)
    }
}

final class CapsuleChromeButton: NSButton {
    var isDark = false {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        let fillColor: NSColor
        let strokeColor: NSColor
        let textColor: NSColor
        if isDark {
            fillColor = NSColor(red: isHighlighted ? 0.15 : 0.09, green: isHighlighted ? 0.18 : 0.11, blue: isHighlighted ? 0.23 : 0.15, alpha: 1)
            strokeColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1) : NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1)
        } else {
            fillColor = NSColor(red: isHighlighted ? 0.92 : 1.0, green: isHighlighted ? 0.94 : 1.0, blue: isHighlighted ? 0.97 : 1.0, alpha: 1)
            strokeColor = NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1) : NSColor(red: 0.64, green: 0.67, blue: 0.72, alpha: 1)
        }

        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = bounds.insetBy(dx: 8, dy: 0)
        let titleSize = title.size(withAttributes: attrs)
        let drawRect = NSRect(
            x: textRect.minX,
            y: max(0, (bounds.height - titleSize.height) / 2),
            width: textRect.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: drawRect, withAttributes: attrs)
    }
}

final class ResizeHandleView: NSView {
    var onDragDeltaX: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        onDragDeltaX?(event.deltaX)
    }
}

final class ClippingView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
