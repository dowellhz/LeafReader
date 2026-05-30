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

final class ReadAloudFloatingSpeedSlider: NSSlider {
    private let speedCell = ReadAloudFloatingSpeedSliderCell()

    convenience init(value: Double, minValue: Double, maxValue: Double, target: Any?, action: Selector?) {
        self.init(frame: .zero)
        self.minValue = minValue
        self.maxValue = maxValue
        doubleValue = value
        self.target = target as AnyObject?
        self.action = action
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = speedCell
        isContinuous = true
        controlSize = .small
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func applyTheme(track: NSColor, fill: NSColor, knob: NSColor, knobStroke: NSColor) {
        speedCell.trackColor = track
        speedCell.fillColor = fill
        speedCell.knobColor = knob
        speedCell.knobStrokeColor = knobStroke
        needsDisplay = true
    }
}

final class ReadAloudFloatingSpeedSliderCell: NSSliderCell {
    var trackColor = NSColor.controlColor
    var fillColor = NSColor.labelColor
    var knobColor = NSColor.labelColor
    var knobStrokeColor = NSColor.clear

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let knobRadius: CGFloat = 7
        let trackRect = NSRect(
            x: rect.minX + knobRadius,
            y: rect.midY - 2,
            width: max(1, rect.width - knobRadius * 2),
            height: 4
        )
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2).fill()

        let denominator = max(0.001, maxValue - minValue)
        let fraction = CGFloat((doubleValue - minValue) / denominator)
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width * min(max(fraction, 0), 1),
            height: trackRect.height
        )
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()

        drawTickDots(in: trackRect)
    }

    override func drawKnob(_ knobRect: NSRect) {
        let size = NSSize(width: 14, height: 14)
        let rect = NSRect(
            x: knobRect.midX - size.width / 2,
            y: knobRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let path = NSBezierPath(ovalIn: rect)
        knobColor.setFill()
        path.fill()
        knobStrokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTickDots(in trackRect: NSRect) {
        guard numberOfTickMarks > 1 else { return }
        for index in 0..<numberOfTickMarks {
            let fraction = CGFloat(index) / CGFloat(numberOfTickMarks - 1)
            let center = NSPoint(x: trackRect.minX + trackRect.width * fraction, y: trackRect.midY)
            let dotRect = NSRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)
            NSColor.white.withAlphaComponent(0.28).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}

final class ReadAloudFloatingControlView: NSView {
    private enum Metrics {
        static let iconButtonWidth: CGFloat = 32
        static let buttonHeight: CGFloat = 30
        static let modeButtonWidth: CGFloat = 58
        static let speedLabelWidth: CGFloat = 30
        static let speedSliderWidth: CGFloat = 92
    }

    let previousButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let playPauseButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let stopButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let replayButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let nextButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let nextPageButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let settingsButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let modeButton = ReadAloudFloatingControlButton(title: "", target: nil, action: nil)
    let speedLabel = NSTextField(labelWithString: AppText.localized("语速", "Speed"))
    let speedSlider = ReadAloudFloatingSpeedSlider(value: 2, minValue: 0, maxValue: 3, target: nil, action: nil)

    private var controlButtons: [ReadAloudFloatingControlButton] {
        [previousButton, playPauseButton, stopButton, replayButton, nextButton, nextPageButton, settingsButton, modeButton]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            previousButton,
            playPauseButton,
            stopButton,
            replayButton,
            nextButton,
            nextPageButton,
            settingsButton,
            speedLabel,
            speedSlider,
            modeButton
        ])
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
        speedLabel.font = AppFont.semibold(ofSize: 12)
        speedLabel.alignment = .right
        speedLabel.lineBreakMode = .byClipping
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.numberOfTickMarks = 4

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            previousButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            playPauseButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            playPauseButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            stopButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            stopButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            replayButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            replayButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            nextButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            nextButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            nextPageButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            nextPageButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            settingsButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth),
            settingsButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            modeButton.widthAnchor.constraint(equalToConstant: Metrics.modeButtonWidth),
            modeButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            speedLabel.widthAnchor.constraint(equalToConstant: Metrics.speedLabelWidth),
            speedSlider.widthAnchor.constraint(equalToConstant: Metrics.speedSliderWidth)
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
        speedLabel.textColor = text.withAlphaComponent(0.86)
        speedSlider.applyTheme(
            track: stroke.withAlphaComponent(0.34),
            fill: text.withAlphaComponent(0.58),
            knob: text.withAlphaComponent(0.92),
            knobStroke: fill.withAlphaComponent(0.72)
        )
        applyModeButtonTitleColor(text)
    }

    func update(
        isPaused: Bool,
        isLoading: Bool,
        mode: ReadAloudAdvanceMode,
        canGoPrevious: Bool,
        speedID: String
    ) {
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
            stopButton,
            symbolName: "stop.fill",
            label: AppText.localized("停止朗读", "Stop reading"),
            isEnabled: true
        )
        configureIconButton(
            replayButton,
            symbolName: "arrow.counterclockwise",
            label: AppText.localized("重播当前句", "Replay current sentence"),
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
        configureIconButton(
            settingsButton,
            symbolName: "gearshape",
            label: AppText.localized("朗读设置", "Speech settings"),
            isEnabled: true
        )
        modeButton.title = mode.title
        modeButton.toolTip = mode.tooltip
        speedLabel.stringValue = AppText.localized("语速", "Speed")
        applyModeButtonTitleColor(modeButton.contentTintColor)
        updateSpeedSlider(speedID: speedID)
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

    func updateSpeedSlider(speedID: String) {
        speedSlider.doubleValue = AISettingsStore.speechSpeedSliderValue(for: speedID)
        speedSlider.toolTip = AppText.localized(
            "语速：\(AISettingsStore.speechSpeedTitle(for: speedID))",
            "Speed: \(AISettingsStore.speechSpeedTitle(for: speedID))"
        )
    }
}
