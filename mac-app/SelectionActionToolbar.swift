import Cocoa

final class SelectionActionToolbar: NSView {
    private enum Metrics {
        static let toolbarCornerRadius: CGFloat = 10
        static let stackSpacing: CGFloat = 4
        static let stackInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        static let buttonWidth: CGFloat = 80
        static let buttonHeight: CGFloat = 36
        static let toolbarHeight: CGFloat = 44
    }

    var onTranslate: (() -> Void)?
    var onExplain: (() -> Void)?
    var onAddWord: (() -> Void)?
    var onSummarize: (() -> Void)?
    var onSpeak: (() -> Void)?
    var onCopy: (() -> Void)?

    private let stack = NSStackView()
    private let translateButton = SelectionActionButton(
        title: AppText.localized("翻译", "Translate"),
        symbolName: "globe",
        target: nil,
        action: nil
    )
    private let explainButton = SelectionActionButton(
        title: AppText.localized("解释", "Explain"),
        symbolName: "text.bubble",
        target: nil,
        action: nil
    )
    private let contextButton = SelectionActionButton(
        title: AppText.localized("总结", "Summarize"),
        symbolName: "list.bullet.rectangle",
        target: nil,
        action: nil
    )
    private let speakButton = SelectionActionButton(
        title: AppText.localized("朗读", "Speak"),
        symbolName: "speaker.wave.2",
        target: nil,
        action: nil
    )
    private let copyButton = SelectionActionButton(
        title: AppText.localized("复制", "Copy"),
        symbolName: "doc.on.doc",
        target: nil,
        action: nil
    )
    private var contextAction: ContextAction = .summarize
    private var showsSpeakButton = true

    private var actionButtons: [SelectionActionButton] {
        [translateButton, explainButton, contextButton, speakButton, copyButton]
    }

    enum ContextAction {
        case addWord
        case summarize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Metrics.toolbarCornerRadius
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        configureStack()
        addSubview(stack)

        configureButton(translateButton, action: #selector(translateTapped))
        configureButton(explainButton, action: #selector(explainTapped))
        configureButton(contextButton, action: #selector(contextTapped))
        configureButton(speakButton, action: #selector(speakTapped))
        configureButton(copyButton, action: #selector(copyTapped))

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyTheme(ReaderTheme.selected)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var preferredSize: CGSize {
        let visibleButtonCount = showsSpeakButton ? 5 : 4
        let horizontalInsets = stack.edgeInsets.left + stack.edgeInsets.right
        let spacing = CGFloat(max(0, visibleButtonCount - 1)) * stack.spacing
        let width = horizontalInsets + spacing + CGFloat(visibleButtonCount) * Metrics.buttonWidth
        return CGSize(width: width, height: Metrics.toolbarHeight)
    }

    func applyTheme(_ theme: ReaderTheme) {
        let background: NSColor
        let border: NSColor
        switch theme {
        case .original:
            background = .white
            border = NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
        case .eyeCare:
            background = NSColor(red: 0.90, green: 0.85, blue: 0.69, alpha: 1)
            border = NSColor(red: 0.66, green: 0.58, blue: 0.38, alpha: 1)
        case .dark:
            background = NSColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1)
            border = NSColor(red: 0.28, green: 0.34, blue: 0.42, alpha: 1)
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = 1
        actionButtons.forEach { $0.applyTheme(theme) }
    }

    func refreshLanguage() {
        translateButton.title = AppText.localized("翻译", "Translate")
        explainButton.title = AppText.localized("解释", "Explain")
        contextButton.title = contextAction == .addWord
            ? AppText.localized("加入单词本", "Add Word")
            : AppText.localized("总结", "Summarize")
        contextButton.symbolName = contextAction == .addWord
            ? "text.badge.plus"
            : "list.bullet.rectangle"
        speakButton.title = AppText.localized("朗读", "Speak")
        copyButton.title = AppText.localized("复制", "Copy")
        actionButtons.forEach { $0.applyTheme(ReaderTheme.selected) }
    }

    func setContextAction(_ action: ContextAction) {
        contextAction = action
        refreshLanguage()
    }

    func setSpeakVisible(_ visible: Bool) {
        showsSpeakButton = visible
        speakButton.isHidden = !visible
        needsLayout = true
    }

    private func configureStack() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = Metrics.stackSpacing
        stack.edgeInsets = Metrics.stackInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func trigger(_ button: NSButton) {
        switch button {
        case translateButton:
            onTranslate?()
        case explainButton:
            onExplain?()
        case contextButton:
            switch contextAction {
            case .addWord:
                onAddWord?()
            case .summarize:
                onSummarize?()
            }
        case speakButton:
            onSpeak?()
        case copyButton:
            onCopy?()
        default:
            break
        }
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(button)
        button.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
    }

    @objc private func translateTapped() {
        onTranslate?()
    }

    @objc private func explainTapped() {
        onExplain?()
    }

    @objc private func contextTapped() {
        trigger(contextButton)
    }

    @objc private func speakTapped() {
        onSpeak?()
    }

    @objc private func copyTapped() {
        onCopy?()
    }
}

final class SelectionActionButton: NSButton {
    private enum Metrics {
        static let cornerRadius: CGFloat = 6
        static let fontSize: CGFloat = 11.5
        static let symbolPointSize: CGFloat = 11
    }

    var symbolName: String? {
        didSet {
            updateSymbol()
        }
    }

    convenience init(title: String, symbolName: String?, target: AnyObject?, action: Selector?) {
        self.init(title: title, target: target, action: action)
        self.symbolName = symbolName
        updateSymbol()
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    func applyTheme(_ theme: ReaderTheme) {
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = true
        let textColor: NSColor
        switch theme {
        case .original:
            layer?.backgroundColor = NSColor(red: 0.96, green: 0.975, blue: 1, alpha: 1).cgColor
            textColor = NSColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1)
        case .eyeCare:
            layer?.backgroundColor = NSColor(red: 0.84, green: 0.77, blue: 0.56, alpha: 1).cgColor
            textColor = NSColor(red: 0.15, green: 0.12, blue: 0.07, alpha: 1)
        case .dark:
            layer?.backgroundColor = NSColor(red: 0.18, green: 0.23, blue: 0.29, alpha: 1).cgColor
            textColor = NSColor(red: 0.88, green: 0.91, blue: 0.96, alpha: 1)
        }
        font = AppFont.semibold(ofSize: Metrics.fontSize)
        contentTintColor = textColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppFont.semibold(ofSize: Metrics.fontSize),
                .foregroundColor: textColor
            ]
        )
        updateSymbol()
    }

    private func updateSymbol() {
        guard let symbolName else {
            image = nil
            imagePosition = .noImage
            return
        }
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.symbolPointSize, weight: .semibold))
        image?.isTemplate = true
        imagePosition = .imageLeft
        imageScaling = .scaleProportionallyDown
    }
}
