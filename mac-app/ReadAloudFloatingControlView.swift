import Cocoa

final class ReadAloudFloatingControlButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        highlight(true)
        defer { highlight(false) }
        if let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class ReadAloudFloatingControlView: NSView {
    private enum Metrics {
        static let iconButtonWidth: CGFloat = 32
        static let buttonHeight: CGFloat = 30
        static let modeButtonWidth: CGFloat = 58
    }

    let previousButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let playPauseButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let nextButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let nextPageButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let modeButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)

    private var controlButtons: [ReadAloudFloatingControlButton] {
        [previousButton, playPauseButton, nextButton, nextPageButton, modeButton]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [previousButton, playPauseButton, nextButton, nextPageButton, modeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for button in controlButtons {
            button.isBordered = false
            button.focusRingType = .none
            button.font = AppFont.semibold(ofSize: 13)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        modeButton.imagePosition = .noImage

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            previousButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            playPauseButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            playPauseButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            nextButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            nextButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            nextPageButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            nextPageButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            modeButton.widthAnchor.constraint(equalToConstant: Metrics.modeButtonWidth),
            modeButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    func applyTheme(_ theme: ReaderTheme) {
        let fill: NSColor
        let stroke: NSColor
        let text: NSColor
        switch theme {
        case .original:
            fill = NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 0.94)
            stroke = NSColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1)
            text = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        case .eyeCare:
            fill = NSColor(red: 0.88, green: 0.82, blue: 0.58, alpha: 0.94)
            stroke = NSColor(red: 0.64, green: 0.50, blue: 0.26, alpha: 1)
            text = NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
        case .dark:
            fill = NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 0.94)
            stroke = NSColor(red: 0.34, green: 0.39, blue: 0.48, alpha: 1)
            text = NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke.cgColor
        for button in controlButtons {
            button.contentTintColor = text
        }
        applyModeButtonTitleColor(text)
    }

    func update(isPaused: Bool, isLoading: Bool, mode: ReadAloudAdvanceMode, canGoPrevious: Bool) {
        configureIconButton(
            previousButton,
            symbolName: "chevron.left",
            label: AppText.localized("上一句", "Previous sentence"),
            isEnabled: !isLoading && canGoPrevious
        )
        configureIconButton(
            playPauseButton,
            symbolName: isLoading ? "hourglass" : (isPaused ? "play.fill" : "pause.fill"),
            label: isPaused ? AppText.localized("继续朗读", "Resume reading") : AppText.localized("暂停朗读", "Pause reading"),
            isEnabled: !isLoading
        )
        configureIconButton(
            nextButton,
            symbolName: "chevron.right",
            label: AppText.localized("下一句", "Next sentence"),
            isEnabled: !isLoading
        )
        configureIconButton(
            nextPageButton,
            symbolName: "chevron.right.2",
            label: AppText.localized("朗读下一页", "Read next page"),
            isEnabled: !isLoading
        )
        modeButton.title = mode.title
        modeButton.toolTip = mode.tooltip
        applyModeButtonTitleColor(modeButton.contentTintColor)
    }

    private func configureIconButton(
        _ button: ReadAloudFloatingControlButton,
        symbolName: String,
        label: String,
        isEnabled: Bool
    ) {
        button.image = TemplateSymbolImage.make(symbolName, accessibilityDescription: label)
        button.isEnabled = isEnabled
        button.toolTip = label
    }

    private func applyModeButtonTitleColor(_ color: NSColor?) {
        guard let color else { return }
        modeButton.attributedTitle = NSAttributedString(
            string: modeButton.title,
            attributes: [.foregroundColor: color, .font: AppFont.semibold(ofSize: 13)]
        )
    }
}
