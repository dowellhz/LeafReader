import Cocoa

final class ThemedSettingsActionButton: NSButton {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }
    var strokeColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var labelColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    private func configure() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imagePosition = .noImage
        alignment = .center
        font = AppFont.semibold(ofSize: 14)
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var title: String {
        didSet { needsDisplay = true }
    }

    override var attributedTitle: NSAttributedString {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (isHighlighted ? fillColor.blended(withFraction: 0.12, of: .black) ?? fillColor : fillColor).setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let displayTitle = !title.isEmpty ? title : attributedTitle.string
        guard !displayTitle.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? AppFont.semibold(ofSize: 14),
            .foregroundColor: labelColor,
            .paragraphStyle: paragraph
        ]
        let titleHeight = displayTitle.size(withAttributes: attrs).height
        let titleRect = NSRect(
            x: 8,
            y: max(0, (bounds.height - titleHeight) / 2),
            width: max(0, bounds.width - 16),
            height: titleHeight
        )
        displayTitle.draw(in: titleRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isHighlighted = true
        let mouseUp = window?.nextEvent(
            matching: [.leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        )
        isHighlighted = false
        guard let mouseUp else { return }
        let location = convert(mouseUp.locationInWindow, from: nil)
        if bounds.contains(location) {
            sendAction(action, to: target)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEnabled, !keyEquivalent.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == keyEquivalent {
            sendAction(action, to: target)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
