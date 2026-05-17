import Cocoa

final class ChatBubbleView: NSView {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var borderColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 8 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class LoadingDotsView: NSView {
    var timer: Timer?
    var phase = 0

    func startAnimating() {
        timer?.invalidate()
        phase = 0
        needsDisplay = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase = (self.phase + 1) % 3
            self.needsDisplay = true
        }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let activeColor = NSColor.systemBlue.withAlphaComponent(0.95)
        let inactiveColor = NSColor.systemBlue.withAlphaComponent(0.28)
        let radius: CGFloat = 3
        let y = bounds.midY - radius
        for index in 0..<3 {
            let color = index == phase ? activeColor : inactiveColor
            color.setFill()
            let x = CGFloat(index) * 8 + 1
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)).fill()
        }
    }
}
