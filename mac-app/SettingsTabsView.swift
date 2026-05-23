import Cocoa

final class SettingsTabsView: NSView {
    enum Style {
        case segmented
        case sidebar
    }

    var onSelectionChanged: ((Int) -> Void)?

    private let labels: [String]
    private let symbols = ["slider.horizontal.3", "cube", "sparkles", "speaker.wave.2", "cylinder.split.1x2"]
    private let style: Style
    private var buttons: [NSButton] = []
    private var selectedIndex = 0

    init(labels: [String], selectedIndex: Int = 0, style: Style = .segmented) {
        self.labels = labels
        self.selectedIndex = selectedIndex
        self.style = style
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        labels = []
        style = .segmented
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        if style == .segmented {
            layer?.backgroundColor = backgroundColor.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = borderColor.cgColor
            layer?.cornerRadius = 14
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = style == .segmented ? .horizontal : .vertical
        stack.distribution = style == .segmented ? .fillEqually : .fill
        stack.alignment = style == .segmented ? .centerY : .leading
        stack.spacing = style == .segmented ? 0 : 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let inset: CGFloat = style == .segmented ? 4 : 4
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: style == .segmented ? inset : 0),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            style == .segmented
                ? stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
                : stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        for (index, text) in labels.enumerated() {
            let button = NSButton(title: text, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.isBordered = false
            button.focusRingType = .none
            button.wantsLayer = true
            button.layer?.cornerRadius = style == .segmented ? 11 : 8
            button.layer?.masksToBounds = true
            button.alignment = style == .segmented ? .center : .left
            if style == .sidebar {
                let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
                let image = NSImage(
                    systemSymbolName: symbols[safe: index] ?? "circle",
                    accessibilityDescription: nil
                )?.withSymbolConfiguration(configuration)
                image?.size = NSSize(width: 26, height: 26)
                button.image = image
                button.imagePosition = .imageLeft
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.imagePosition = .noImage
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            if style == .sidebar {
                button.widthAnchor.constraint(equalToConstant: 140).isActive = true
                button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            }
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

    func refreshTheme() {
        if style == .segmented {
            layer?.backgroundColor = backgroundColor.cgColor
            layer?.borderColor = borderColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        updateAppearance()
    }

    func selectIndex(_ index: Int) {
        guard labels.indices.contains(index) else { return }
        selectedIndex = index
        updateAppearance()
    }

    private func updateAppearance() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.backgroundColor = selected
                ? selectedBackgroundColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = selected ? selectedTextColor : textColor
            button.attributedTitle = NSAttributedString(
                string: style == .sidebar ? "  \(labels[index])" : labels[index],
                attributes: [
                    .font: AppFont.semibold(ofSize: style == .segmented ? 15 : 16),
                    .foregroundColor: selected
                        ? selectedTextColor
                        : textColor
                ]
            )
        }
    }

    private var backgroundColor: NSColor {
        switch ReaderTheme.selected {
        case .original:
            return NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.84, green: 0.79, blue: 0.63, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    private var selectedBackgroundColor: NSColor {
        switch ReaderTheme.selected {
        case .original:
            return NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.86, blue: 0.70, alpha: 1)
        case .dark:
            return NSColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1)
        }
    }

    private var borderColor: NSColor {
        switch ReaderTheme.selected {
        case .original:
            return NSColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    private var textColor: NSColor {
        switch ReaderTheme.selected {
        case .original:
            return NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
        case .dark:
            return NSColor(red: 0.76, green: 0.80, blue: 0.86, alpha: 1)
        }
    }

    private var selectedTextColor: NSColor {
        switch ReaderTheme.selected {
        case .original:
            return NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.25, green: 0.19, blue: 0.09, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
