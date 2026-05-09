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
