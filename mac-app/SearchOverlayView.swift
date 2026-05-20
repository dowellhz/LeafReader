import Cocoa

final class SearchOverlayView: NSView {
    let searchField = NSTextField(string: "")
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    var onSubmit: ((String) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    func setResultText(_ text: String) {
        resultLabel.stringValue = text
    }

    func setDarkMode(_ enabled: Bool) {
        setTheme(enabled ? .dark : .original)
    }

    func setTheme(_ theme: ReaderTheme) {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let textColor: NSColor
        let secondaryColor: NSColor
        switch theme {
        case .original:
            backgroundColor = NSColor(red: 0.995, green: 0.985, blue: 0.995, alpha: 0.98)
            borderColor = .clear
            textColor = NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
            secondaryColor = NSColor(red: 0.42, green: 0.42, blue: 0.47, alpha: 1)
        case .eyeCare:
            backgroundColor = NSColor(red: 0.90, green: 0.85, blue: 0.70, alpha: 0.98)
            borderColor = NSColor(red: 0.67, green: 0.60, blue: 0.42, alpha: 1)
            textColor = NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
            secondaryColor = NSColor(red: 0.43, green: 0.37, blue: 0.25, alpha: 1)
        case .dark:
            backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 0.98)
            borderColor = NSColor(red: 0.24, green: 0.28, blue: 0.34, alpha: 1)
            textColor = NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
            secondaryColor = NSColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1)
        }
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderWidth = theme == .original ? 0 : 1
        layer?.borderColor = borderColor.cgColor
        searchField.textColor = textColor
        resultLabel.textColor = secondaryColor
        for button in [previousButton, nextButton, closeButton] {
            button.contentTintColor = secondaryColor
        }
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.995, green: 0.985, blue: 0.995, alpha: 0.98).cgColor
        layer?.cornerRadius = 14
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -7)

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 18)
        searchField.placeholderString = AppText.localized("搜索文档", "Search document")
        searchField.target = self
        searchField.action = #selector(submitSearch)
        searchField.cell?.sendsActionOnEndEditing = false

        resultLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        resultLabel.textColor = NSColor(red: 0.42, green: 0.42, blue: 0.47, alpha: 1)
        resultLabel.alignment = .right

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(red: 0.82, green: 0.72, blue: 0.98, alpha: 0.65).cgColor

        configureIconButton(previousButton, symbol: "chevron.up", action: #selector(previousResult))
        configureIconButton(nextButton, symbol: "chevron.down", action: #selector(nextResult))
        configureIconButton(closeButton, symbol: "xmark", action: #selector(closeSearch))

        for view in [searchField, resultLabel, separator, previousButton, nextButton, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: resultLabel.leadingAnchor, constant: -12),

            resultLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resultLabel.widthAnchor.constraint(equalToConstant: 72),

            separator.leadingAnchor.constraint(equalTo: resultLabel.trailingAnchor, constant: 18),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 44),

            previousButton.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 18),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 14),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),

            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 18),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.target = self
        button.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(red: 0.44, green: 0.44, blue: 0.48, alpha: 1)
    }

    @objc private func submitSearch() {
        onSubmit?(searchField.stringValue)
    }

    @objc private func previousResult() {
        onPrevious?()
    }

    @objc private func nextResult() {
        onNext?()
    }

    @objc private func closeSearch() {
        onClose?()
    }
}
