import Cocoa

final class ThemedSettingsCheckbox: NSButton {
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure(title: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(title: "")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    convenience init(title: String) {
        self.init(frame: .zero)
        configure(title: title)
    }

    private func configure(title: String) {
        self.title = title
        setButtonType(.toggle)
        isBordered = false
        imagePosition = .noImage
        alignment = .left
        attributedTitle = NSAttributedString(string: "")
        attributedAlternateTitle = NSAttributedString(string: "")
    }

    override var intrinsicContentSize: NSSize {
        let titleWidth = title.isEmpty
            ? 0
            : (title as NSString).size(withAttributes: [.font: font ?? AppFont.semibold(ofSize: 14)]).width + 8
        return NSSize(width: 22 + titleWidth, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let boxRect = NSRect(x: 2, y: (bounds.height - 18) / 2, width: 18, height: 18)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 5, yRadius: 5)
        (state == .on ? selectedFillColor : backgroundColor).setFill()
        boxPath.fill()
        borderColor.setStroke()
        boxPath.lineWidth = 1
        boxPath.stroke()

        if state == .on {
            checkColor.setStroke()
            let left = NSPoint(x: boxRect.minX + 4.2, y: boxRect.midY - 0.5)
            let middle = NSPoint(x: boxRect.minX + 7.6, y: boxRect.minY + 4.6)
            let right = NSPoint(x: boxRect.maxX - 3.8, y: boxRect.maxY - 4.8)
            let check = NSBezierPath()
            check.lineWidth = 2.4
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: pointForCurrentCoordinateSystem(left, in: boxRect))
            check.line(to: pointForCurrentCoordinateSystem(middle, in: boxRect))
            check.line(to: pointForCurrentCoordinateSystem(right, in: boxRect))
            check.stroke()
        }

        guard !title.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? AppFont.semibold(ofSize: 14),
            .foregroundColor: textColor
        ]
        let titleSize = title.size(withAttributes: attrs)
        title.draw(
            at: NSPoint(x: boxRect.maxX + 8, y: max(0, (bounds.height - titleSize.height) / 2)),
            withAttributes: attrs
        )
    }

    private func pointForCurrentCoordinateSystem(_ point: NSPoint, in rect: NSRect) -> NSPoint {
        guard isFlipped else { return point }
        return NSPoint(x: point.x, y: rect.minY + rect.maxY - point.y)
    }

    override func mouseDown(with event: NSEvent) {
        state = state == .on ? .off : .on
        needsDisplay = true
        sendAction(action, to: target)
    }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    private var backgroundColor: NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.88, green: 0.83, blue: 0.68, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    private var selectedFillColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }

    private var borderColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.68, green: 0.72, blue: 0.80, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.58, green: 0.48, blue: 0.28, alpha: 1)
        case .dark:
            return NSColor(red: 0.38, green: 0.45, blue: 0.54, alpha: 1)
        }
    }

    private var checkColor: NSColor {
        switch theme {
        case .original, .dark:
            return .white
        case .eyeCare:
            return NSColor(red: 0.97, green: 0.93, blue: 0.78, alpha: 1)
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
}
