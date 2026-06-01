import Cocoa

final class ReadAloudShortcutHintView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let titleFontSize: CGFloat = 15
        static let outerHorizontalInset: CGFloat = 18
        static let stackHorizontalInset: CGFloat = 16
        static let topInset: CGFloat = 13
        static let titleToStackSpacing: CGFloat = 9
        static let bottomInset: CGFloat = 12
        static let itemSpacing: CGFloat = 12
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let itemStack = NSStackView()
    private var keyItems: [ReadAloudShortcutKeyItemView] = []

    var text: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.borderWidth = Metrics.borderWidth
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppFont.semibold(ofSize: Metrics.titleFontSize)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byClipping
        addSubview(titleLabel)

        keyItems = Self.defaultItems()
        itemStack.orientation = .horizontal
        itemStack.alignment = .top
        itemStack.distribution = .fillEqually
        itemStack.spacing = Metrics.itemSpacing
        itemStack.translatesAutoresizingMaskIntoConstraints = false
        keyItems.forEach { itemStack.addArrangedSubview($0) }
        addSubview(itemStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topInset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.outerHorizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.outerHorizontalInset),

            itemStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleToStackSpacing),
            itemStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.stackHorizontalInset),
            itemStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.stackHorizontalInset),
            itemStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.bottomInset)
        ])
    }

    func applyTheme(_ theme: ReaderTheme) {
        let palette = Self.palette(for: theme)
        layer?.backgroundColor = palette.fill.cgColor
        layer?.borderColor = palette.stroke.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        titleLabel.textColor = palette.text
        keyItems.forEach {
            $0.applyTheme(fill: palette.fill, stroke: palette.stroke, text: palette.text)
        }
    }

    private static func defaultItems() -> [ReadAloudShortcutKeyItemView] {
        [
            ReadAloudShortcutKeyItemView(
                keyTop: "{",
                keyBottom: "[",
                title: AppText.localized("后退", "Back")
            ),
            ReadAloudShortcutKeyItemView(
                keyTop: "}",
                keyBottom: "]",
                title: AppText.localized("重播", "Replay")
            ),
            ReadAloudShortcutKeyItemView(
                keyTop: "|",
                keyBottom: "\\",
                title: AppText.localized("前进", "Forward")
            )
        ]
    }

    private static func palette(for theme: ReaderTheme) -> (fill: NSColor, stroke: NSColor, text: NSColor) {
        switch theme {
        case .original:
            return (
                NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 0.96),
                NSColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1),
                NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            )
        case .eyeCare:
            return (
                NSColor(red: 0.88, green: 0.82, blue: 0.58, alpha: 0.96),
                NSColor(red: 0.64, green: 0.50, blue: 0.26, alpha: 1),
                NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
            )
        case .dark:
            return (
                NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 0.96),
                NSColor(red: 0.34, green: 0.39, blue: 0.48, alpha: 1),
                NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            )
        }
    }
}

private final class ReadAloudShortcutKeyItemView: NSView {
    private enum Metrics {
        static let keycapWidth: CGFloat = 72
        static let keycapHeight: CGFloat = 56
        static let keycapCornerRadius: CGFloat = 12
        static let keycapBorderWidth: CGFloat = 1.5
        static let keyFontSize: CGFloat = 19
        static let titleFontSize: CGFloat = 15
        static let keyTopOffset: CGFloat = -9
        static let keyBottomOffset: CGFloat = 13
        static let titleSpacing: CGFloat = 6
    }

    private let keycapView = NSView()
    private let keyTopLabel = NSTextField(labelWithString: "")
    private let keyBottomLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(keyTop: String, keyBottom: String, title: String) {
        super.init(frame: .zero)
        keyTopLabel.stringValue = keyTop
        keyBottomLabel.stringValue = keyBottom
        titleLabel.stringValue = title
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        keycapView.translatesAutoresizingMaskIntoConstraints = false
        keycapView.wantsLayer = true
        keycapView.layer?.cornerRadius = Metrics.keycapCornerRadius
        keycapView.layer?.borderWidth = Metrics.keycapBorderWidth
        addSubview(keycapView)

        for label in [keyTopLabel, keyBottomLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = AppFont.semibold(ofSize: Metrics.keyFontSize)
            label.alignment = .center
            keycapView.addSubview(label)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppFont.semibold(ofSize: Metrics.titleFontSize)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byClipping
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            keycapView.topAnchor.constraint(equalTo: topAnchor),
            keycapView.centerXAnchor.constraint(equalTo: centerXAnchor),
            keycapView.widthAnchor.constraint(equalToConstant: Metrics.keycapWidth),
            keycapView.heightAnchor.constraint(equalToConstant: Metrics.keycapHeight),

            keyTopLabel.centerXAnchor.constraint(equalTo: keycapView.centerXAnchor),
            keyTopLabel.centerYAnchor.constraint(equalTo: keycapView.centerYAnchor, constant: Metrics.keyTopOffset),
            keyBottomLabel.centerXAnchor.constraint(equalTo: keycapView.centerXAnchor),
            keyBottomLabel.centerYAnchor.constraint(equalTo: keycapView.centerYAnchor, constant: Metrics.keyBottomOffset),

            titleLabel.topAnchor.constraint(equalTo: keycapView.bottomAnchor, constant: Metrics.titleSpacing),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func applyTheme(fill: NSColor, stroke: NSColor, text: NSColor) {
        keycapView.layer?.backgroundColor = fill.withAlphaComponent(0.42).cgColor
        keycapView.layer?.borderColor = stroke.cgColor
        keyTopLabel.textColor = text
        keyBottomLabel.textColor = text
        titleLabel.textColor = text
    }
}
