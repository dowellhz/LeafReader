import Cocoa

enum HelpFeatureIcon {
    case reading
    case qa
    case vocabulary
    case shelf

    var foreground: NSColor {
        switch self {
        case .reading: return NSColor(calibratedRed: 0.25, green: 0.70, blue: 0.15, alpha: 1)
        case .qa: return NSColor(calibratedRed: 0.45, green: 0.24, blue: 0.78, alpha: 1)
        case .vocabulary: return NSColor(calibratedRed: 0.09, green: 0.45, blue: 0.98, alpha: 1)
        case .shelf: return NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.00, alpha: 1)
        }
    }

    var background: NSColor {
        switch self {
        case .reading: return NSColor(calibratedRed: 0.88, green: 0.97, blue: 0.85, alpha: 1)
        case .qa: return NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.98, alpha: 1)
        case .vocabulary: return NSColor(calibratedRed: 0.86, green: 0.93, blue: 1.00, alpha: 1)
        case .shelf: return NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.83, alpha: 1)
        }
    }
}

final class HelpCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class HelpVersionBadgeView: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.90, green: 0.99, blue: 0.89, alpha: 1).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.25, green: 0.74, blue: 0.27, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.17, green: 0.63, blue: 0.18, alpha: 1)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class HelpTipView: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.93, green: 1.00, blue: 0.96, alpha: 0.78).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.55, green: 0.86, blue: 0.66, alpha: 0.85).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6

        let icon = HelpLeafIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: AppText.localized("小贴士", "Tip"))
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        addSubview(title)

        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 11),

            label.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class HelpFeatureIconView: NSView {
    private let icon: HelpFeatureIcon

    init(icon: HelpFeatureIcon) {
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = bounds.insetBy(dx: 0, dy: 0)
        icon.background.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        if icon == .vocabulary {
            drawLetter(in: bounds.insetBy(dx: 15, dy: 14))
            return
        }

        guard let gradient = NSGradient(starting: icon.foreground.withAlphaComponent(0.88), ending: icon.foreground) else {
            icon.foreground.setFill()
            drawSymbol(in: bounds.insetBy(dx: 16, dy: 16))
            return
        }
        NSGraphicsContext.saveGraphicsState()
        drawSymbolClip(in: bounds.insetBy(dx: 16, dy: 16))
        gradient.draw(in: bounds, angle: -35)
        NSGraphicsContext.restoreGraphicsState()
        drawSymbolDetails(in: bounds.insetBy(dx: 16, dy: 16))
    }

    private func drawSymbolClip(in rect: NSRect) {
        let path = symbolPath(in: rect)
        path.addClip()
    }

    private func drawSymbol(in rect: NSRect) {
        symbolPath(in: rect).fill()
    }

    private func symbolPath(in rect: NSRect) -> NSBezierPath {
        switch icon {
        case .reading:
            return bookPath(in: rect)
        case .qa:
            return bubblePath(in: rect)
        case .vocabulary:
            return letterPath(in: rect)
        case .shelf:
            return shelfPath(in: rect)
        }
    }

    private func bookPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let gap: CGFloat = rect.width * 0.08
        let pageWidth = (rect.width - gap) / 2
        let left = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.06, width: pageWidth, height: rect.height * 0.88)
        let right = NSRect(x: rect.minX + pageWidth + gap, y: left.minY, width: pageWidth, height: left.height)
        path.append(NSBezierPath(roundedRect: left, xRadius: 7, yRadius: 7))
        path.append(NSBezierPath(roundedRect: right, xRadius: 7, yRadius: 7))
        return path
    }

    private func bubblePath(in rect: NSRect) -> NSBezierPath {
        let bubbleRect = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.23, width: rect.width, height: rect.height * 0.68)
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 12, yRadius: 12)
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.26, y: bubbleRect.minY + 2))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.15, y: bubbleRect.minY + rect.height * 0.22))
        path.close()
        return path
    }

    private func letterPath(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(rect: rect)
    }

    private func shelfPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let base = NSRect(x: rect.minX - 1, y: rect.minY + 1, width: rect.width + 2, height: 6)
        path.append(NSBezierPath(roundedRect: base, xRadius: 3, yRadius: 3))

        let bookWidth = rect.width * 0.24
        let bookRects = [
            NSRect(x: rect.minX + rect.width * 0.08, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.62),
            NSRect(x: rect.midX - bookWidth / 2, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.82),
            NSRect(x: rect.maxX - rect.width * 0.08 - bookWidth, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.68)
        ]
        for book in bookRects {
            path.append(NSBezierPath(roundedRect: book, xRadius: 3, yRadius: 3))
            path.append(NSBezierPath(roundedRect: NSRect(x: book.midX - 2.5, y: book.maxY - book.height * 0.48, width: 5, height: book.height * 0.28), xRadius: 2.5, yRadius: 2.5))
            path.append(NSBezierPath(roundedRect: NSRect(x: book.minX + 2, y: book.minY + 9, width: book.width - 4, height: 2.5), xRadius: 1.25, yRadius: 1.25))
        }
        return path
    }

    private func drawLetter(in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: rect.height * 1.2, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: icon.foreground
        ]
        let size = ("A" as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * 0.03)
        ("A" as NSString).draw(at: point, withAttributes: attributes)
    }

    private func drawSymbolDetails(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.88).setFill()
        switch icon {
        case .reading:
            let columnWidth = rect.width * 0.11
            let columnHeight = rect.height * 0.48
            let y = rect.midY - columnHeight / 2
            NSBezierPath(roundedRect: NSRect(x: rect.minX + rect.width * 0.23, y: y, width: columnWidth, height: columnHeight), xRadius: columnWidth / 2, yRadius: columnWidth / 2).fill()
            NSBezierPath(roundedRect: NSRect(x: rect.maxX - rect.width * 0.23 - columnWidth, y: y, width: columnWidth, height: columnHeight), xRadius: columnWidth / 2, yRadius: columnWidth / 2).fill()
        case .qa:
            let radius = rect.width * 0.075
            for index in 0..<3 {
                let x = rect.midX - radius * 3.2 + CGFloat(index) * radius * 3.2
                NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - radius * 0.2, width: radius * 2, height: radius * 2)).fill()
            }
        case .shelf:
            for x in [rect.minX + rect.width * 0.20, rect.midX, rect.maxX - rect.width * 0.20] {
                NSBezierPath(roundedRect: NSRect(x: x - 2.3, y: rect.minY + rect.height * 0.50, width: 4.6, height: rect.height * 0.22), xRadius: 2.3, yRadius: 2.3).fill()
            }
            for y in [rect.minY + 13, rect.minY + 18] {
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 5, y: y, width: rect.width - 10, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            }
        case .vocabulary:
            break
        }
    }
}

final class HelpLeafIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let green = NSColor(calibratedRed: 0.19, green: 0.68, blue: 0.31, alpha: 1)
        green.setStroke()
        green.setFill()

        let leafRect = bounds.insetBy(dx: 5, dy: 4)
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: leafRect.minX + leafRect.width * 0.15, y: leafRect.minY + leafRect.height * 0.34))
        leaf.curve(
            to: NSPoint(x: leafRect.maxX, y: leafRect.maxY),
            controlPoint1: NSPoint(x: leafRect.minX + leafRect.width * 0.18, y: leafRect.maxY),
            controlPoint2: NSPoint(x: leafRect.maxX * 0.86, y: leafRect.maxY * 0.98)
        )
        leaf.curve(
            to: NSPoint(x: leafRect.minX + leafRect.width * 0.15, y: leafRect.minY + leafRect.height * 0.34),
            controlPoint1: NSPoint(x: leafRect.maxX * 0.93, y: leafRect.minY + leafRect.height * 0.18),
            controlPoint2: NSPoint(x: leafRect.minX + leafRect.width * 0.38, y: leafRect.minY + leafRect.height * 0.02)
        )
        leaf.lineWidth = 2
        leaf.stroke()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: bounds.minX + 5, y: bounds.minY + 4))
        stem.curve(
            to: NSPoint(x: leafRect.maxX - 2, y: leafRect.maxY - 2),
            controlPoint1: NSPoint(x: leafRect.minX + leafRect.width * 0.32, y: leafRect.minY + leafRect.height * 0.42),
            controlPoint2: NSPoint(x: leafRect.minX + leafRect.width * 0.62, y: leafRect.minY + leafRect.height * 0.68)
        )
        stem.lineWidth = 2
        stem.stroke()
    }
}

