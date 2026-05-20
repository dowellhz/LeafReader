import Cocoa

final class SettingsTabsView: NSView {
    var onSelectionChanged: ((Int) -> Void)?

    private let labels: [String]
    private var buttons: [NSButton] = []
    private var selectedIndex = 0

    init(labels: [String], selectedIndex: Int = 0) {
        self.labels = labels
        self.selectedIndex = selectedIndex
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
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = borderColor.cgColor
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

    func refreshTheme() {
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
        updateAppearance()
    }

    private func updateAppearance() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.backgroundColor = selected
                ? selectedBackgroundColor.cgColor
                : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(
                string: labels[index],
                attributes: [
                    .font: AppFont.semibold(ofSize: 18),
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
            return .white
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
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.25, green: 0.19, blue: 0.09, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
        }
    }
}
