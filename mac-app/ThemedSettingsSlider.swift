import Cocoa

final class ThemedSettingsSlider: NSControl {
    let minValue: Double
    let maxValue: Double
    private var currentValue: Double = 0
    var numberOfTickMarks: Int = 0 {
        didSet { needsDisplay = true }
    }
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    override var doubleValue: Double {
        get {
            currentValue
        }
        set {
            currentValue = min(max(newValue, minValue), maxValue)
            needsDisplay = true
        }
    }

    init(value: Double, minValue: Double, maxValue: Double) {
        self.minValue = minValue
        self.maxValue = maxValue
        super.init(frame: .zero)
        currentValue = min(max(value, minValue), maxValue)
    }

    required init?(coder: NSCoder) {
        minValue = 0
        maxValue = 1
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackHeight: CGFloat = 4
        let knobSize = NSSize(width: 18, height: 28)
        let trackRect = NSRect(
            x: knobSize.width / 2,
            y: (bounds.height - trackHeight) / 2,
            width: max(1, bounds.width - knobSize.width),
            height: trackHeight
        )
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        trackColor.setFill()
        trackPath.fill()

        if numberOfTickMarks > 1 {
            tickColor.setStroke()
            for index in 0..<numberOfTickMarks {
                let ratio = CGFloat(index) / CGFloat(numberOfTickMarks - 1)
                let x = trackRect.minX + trackRect.width * ratio
                let tickPath = NSBezierPath()
                tickPath.lineWidth = 2
                tickPath.move(to: NSPoint(x: x, y: trackRect.midY - 6))
                tickPath.line(to: NSPoint(x: x, y: trackRect.midY + 6))
                tickPath.stroke()
            }
        }

        let fillWidth = trackRect.width * CGFloat(valueRatio)
        if fillWidth > 0 {
            let filledRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height)
            let filledPath = NSBezierPath(roundedRect: filledRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
            fillColor.setFill()
            filledPath.fill()
        }

        let knobCenterX = trackRect.minX + trackRect.width * CGFloat(valueRatio)
        let knobRect = NSRect(
            x: knobCenterX - knobSize.width / 2,
            y: (bounds.height - knobSize.height) / 2,
            width: knobSize.width,
            height: knobSize.height
        )
        let knobPath = NSBezierPath(roundedRect: knobRect, xRadius: 7, yRadius: 7)
        knobColor.setFill()
        knobPath.fill()
        knobBorderColor.setStroke()
        knobPath.lineWidth = 1
        knobPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        updateValue(with: event)
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { [weak self] event, stop in
            guard let self, let event else { return }
            switch event.type {
            case .leftMouseDragged:
                self.updateValue(with: event)
            case .leftMouseUp:
                stop.pointee = true
            default:
                break
            }
        }
    }

    private func updateValue(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inset: CGFloat = 9
        let usableWidth = max(1, bounds.width - inset * 2)
        let ratio = min(max((point.x - inset) / usableWidth, 0), 1)
        doubleValue = minValue + Double(ratio) * (maxValue - minValue)
        sendAction(action, to: target)
    }

    private var valueRatio: Double {
        guard maxValue > minValue else { return 0 }
        return (doubleValue - minValue) / (maxValue - minValue)
    }

    private var trackColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.80, green: 0.83, blue: 0.88, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.76, green: 0.70, blue: 0.52, alpha: 1)
        case .dark:
            return NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    private var fillColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }

    private var tickColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.68, green: 0.71, blue: 0.78, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.65, green: 0.58, blue: 0.40, alpha: 1)
        case .dark:
            return NSColor(red: 0.36, green: 0.42, blue: 0.50, alpha: 1)
        }
    }

    private var knobColor: NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.86, blue: 0.70, alpha: 1)
        case .dark:
            return NSColor(red: 0.17, green: 0.21, blue: 0.27, alpha: 1)
        }
    }

    private var knobBorderColor: NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.74, green: 0.77, blue: 0.84, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.58, green: 0.48, blue: 0.28, alpha: 1)
        case .dark:
            return NSColor(red: 0.42, green: 0.49, blue: 0.58, alpha: 1)
        }
    }
}
