import Cocoa

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class GradientButton: NSButton {
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

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
            let gradient = NSGradient(colors: enabledGradientColors)
            gradient?.draw(in: path, angle: 0)
            enabledStrokeColor.setStroke()
        } else {
            disabledFillColor.setFill()
            path.fill()
            disabledStrokeColor.setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        let title = AppText.askAI
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 16),
            .foregroundColor: isEnabled ? NSColor.white : disabledTextColor
        ]
        let previewAttrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13),
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

    private var enabledGradientColors: [NSColor] {
        switch theme {
        case .original:
            return [
                NSColor(red: 0.45, green: 0.18, blue: 0.96, alpha: 1),
                NSColor(red: 0.21, green: 0.50, blue: 0.98, alpha: 1)
            ]
        case .eyeCare:
            return [
                NSColor(red: 0.66, green: 0.43, blue: 0.13, alpha: 1),
                NSColor(red: 0.40, green: 0.53, blue: 0.24, alpha: 1)
            ]
        case .dark:
            return [
                NSColor(red: 0.34, green: 0.24, blue: 0.78, alpha: 1),
                NSColor(red: 0.16, green: 0.42, blue: 0.84, alpha: 1)
            ]
        }
    }

    private var enabledStrokeColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.25, green: 0.33, blue: 0.92, alpha: 0.24)
        case .eyeCare:
            return NSColor(red: 0.46, green: 0.33, blue: 0.14, alpha: 0.30)
        case .dark:
            return NSColor(red: 0.24, green: 0.36, blue: 0.88, alpha: 0.30)
        }
    }

    private var disabledFillColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.86, green: 0.81, blue: 0.66, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    private var disabledStrokeColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.70, green: 0.64, blue: 0.46, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)
        }
    }

    private var disabledTextColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.70, green: 0.71, blue: 0.76, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.54, green: 0.47, blue: 0.30, alpha: 1)
        case .dark:
            return NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1)
        }
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
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    var isDark = false {
        didSet {
            theme = isDark ? .dark : .original
            needsDisplay = true
        }
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

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13)
        ]
        let textWidth = title.size(withAttributes: attrs).width
        return NSSize(width: max(64, ceil(textWidth) + 28), height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        let fillColor: NSColor
        let strokeColor: NSColor
        let textColor: NSColor
        switch theme {
        case .dark:
            fillColor = NSColor(red: isHighlighted ? 0.15 : 0.09, green: isHighlighted ? 0.18 : 0.11, blue: isHighlighted ? 0.23 : 0.15, alpha: 1)
            strokeColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1) : NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1)
        case .eyeCare:
            fillColor = NSColor(red: isHighlighted ? 0.82 : 0.88, green: isHighlighted ? 0.76 : 0.82, blue: isHighlighted ? 0.58 : 0.66, alpha: 1)
            strokeColor = NSColor(red: 0.66, green: 0.60, blue: 0.43, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1) : NSColor(red: 0.54, green: 0.48, blue: 0.33, alpha: 1)
        case .original:
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
            .font: AppFont.semibold(ofSize: 13),
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

final class SearchUnderlineButton: NSButton {
    var isDark = false {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
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
        let lineColor = isDark
            ? NSColor(red: 0.42, green: 0.48, blue: 0.56, alpha: isHighlighted ? 1 : 0.8)
            : NSColor(red: 0.72, green: 0.76, blue: 0.82, alpha: isHighlighted ? 1 : 0.9)
        lineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let underlineY = bounds.isEmpty ? 0 : bounds.height - 4
        path.move(to: NSPoint(x: 0, y: underlineY))
        path.line(to: NSPoint(x: bounds.width, y: underlineY))
        path.stroke()
    }
}

final class ResizeHandleView: NSView {
    var onDragDeltaX: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

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

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }
}

final class ClippingView: NSView {
    var onDroppedDocumentURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ReaderFileDrop.perform(sender) { [weak self] urls in
            self?.onDroppedDocumentURLs?(urls)
        }
    }
}

final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
