import Cocoa

final class ReadAloudSoftHintView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = ThemedSettingsActionButton(title: AppText.localized("查看", "View"), target: nil, action: nil)

    var onAction: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: AppText.localized("关联笔记", "Linked notes"))
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppFont.semibold(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.title = AppText.localized("查看", "View")
        actionButton.font = AppFont.semibold(ofSize: 13)
        actionButton.target = self
        actionButton.action = #selector(performAction(_:))
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -14),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 64),
            actionButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        applyTheme(ReaderTheme.selected)
    }

    func applyTheme(_ theme: ReaderTheme) {
        let fill: NSColor
        let stroke: NSColor
        let title: NSColor
        let accent: NSColor
        let buttonText: NSColor
        switch theme {
        case .original:
            fill = NSColor.white.withAlphaComponent(0.98)
            stroke = NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            title = NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            accent = NSColor(red: 0.22, green: 0.50, blue: 0.98, alpha: 1)
            buttonText = .white
        case .eyeCare:
            fill = NSColor(red: 0.91, green: 0.87, blue: 0.73, alpha: 0.98)
            stroke = NSColor(red: 0.67, green: 0.61, blue: 0.45, alpha: 1)
            title = NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
            accent = NSColor(red: 0.62, green: 0.40, blue: 0.13, alpha: 1)
            buttonText = .white
        case .dark:
            fill = NSColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 0.98)
            stroke = NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1)
            title = NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
            accent = NSColor(red: 0.76, green: 0.62, blue: 0.32, alpha: 1)
            buttonText = NSColor(red: 0.08, green: 0.07, blue: 0.05, alpha: 1)
        }

        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        titleLabel.textColor = title
        iconView.contentTintColor = accent
        actionButton.fillColor = accent
        actionButton.strokeColor = accent
        actionButton.labelColor = buttonText
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }

    @objc private func performAction(_ sender: Any?) {
        onAction?()
    }
}
