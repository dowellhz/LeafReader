import Cocoa

final class SettingsTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "c":
            editor.copySelectionToClipboard()
            return true
        case "x":
            editor.copySelectionToClipboard()
            editor.delete(nil)
            return true
        case "v":
            editor.pasteStringFromClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class SettingsTabsView: NSView {
    var onSelectionChanged: ((Int) -> Void)?

    private let labels: [String]
    private var buttons: [NSButton] = []
    private var selectedIndex = 0

    init(labels: [String]) {
        self.labels = labels
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        labels = []
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1).cgColor
        layer?.cornerRadius = 16
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        for (index, text) in labels.enumerated() {
            let button = NSButton(title: text, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.layer?.masksToBounds = true
            button.translatesAutoresizingMaskIntoConstraints = false
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        updateAppearance()
    }

    @objc private func selectTab(_ sender: NSButton) {
        selectedIndex = sender.tag
        updateAppearance()
        onSelectionChanged?(selectedIndex)
    }

    private func updateAppearance() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.backgroundColor = selected
                ? NSColor.white.cgColor
                : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(
                string: labels[index],
                attributes: [
                    .font: AppFont.semibold(ofSize: 18),
                    .foregroundColor: selected
                        ? NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
                        : NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
                ]
            )
        }
    }
}

final class VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        return constrained
    }

    override var bounds: NSRect {
        get {
            var current = super.bounds
            current.origin.x = 0
            return current
        }
        set {
            var next = newValue
            next.origin.x = 0
            super.bounds = next
        }
    }
}
