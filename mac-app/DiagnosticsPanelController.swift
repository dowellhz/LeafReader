import Cocoa

final class DiagnosticsPanelController: NSWindowController {
    private let rowsProvider: () -> [DiagnosticRow]
    private let panelSize = NSSize(width: 560, height: 500)

    init(rowsProvider: @escaping () -> [DiagnosticRow]) {
        self.rowsProvider = rowsProvider
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(attachedTo parentWindow: NSWindow?) {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        if let parentWindow {
            let parentFrame = parentWindow.frame
            window.setFrameOrigin(NSPoint(
                x: parentFrame.midX - panelSize.width / 2,
                y: parentFrame.midY - panelSize.height / 2
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let theme = DiagnosticsPanelTheme.make(from: ReaderTheme.selected)
        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("Leaf Reader 诊断", "Leaf Reader Diagnostics")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.appearance = theme.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.contentView = makeContentView(theme: theme)
        return panel
    }

    private func makeContentView(theme: DiagnosticsPanelTheme) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: panelSize))
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.backgroundColor.cgColor
        root.layer?.borderWidth = 1
        root.layer?.borderColor = theme.borderColor.cgColor
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = theme.isDark ? 0.42 : 0.22
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)

        let titleIcon = NSImageView()
        titleIcon.image = NSImage(systemSymbolName: "calendar.badge.checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
        titleIcon.contentTintColor = theme.primaryText
        titleIcon.imageScaling = .scaleNone
        titleIcon.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleIcon)

        let titleLabel = NSTextField(labelWithString: AppText.localized("运行状态", "Runtime Status"))
        titleLabel.font = AppFont.semibold(ofSize: 22)
        titleLabel.textColor = theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        let closeIconButton = NSButton(title: "", target: self, action: #selector(closePanel(_:)))
        closeIconButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        closeIconButton.isBordered = false
        closeIconButton.contentTintColor = theme.secondaryText
        closeIconButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(closeIconButton)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        for row in rowsProvider() {
            let rowView = diagnosticRowView(row, theme: theme)
            stack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let copyButton = actionButton(
            title: AppText.localized("复制诊断", "Copy Diagnostics"),
            primary: false,
            theme: theme,
            action: #selector(copyDiagnostics(_:))
        )
        root.addSubview(copyButton)

        let closeButton = actionButton(
            title: AppText.close,
            primary: true,
            theme: theme,
            action: #selector(closePanel(_:))
        )
        root.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleIcon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleIcon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            titleIcon.widthAnchor.constraint(equalToConstant: 28),
            titleIcon.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: titleIcon.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeIconButton.leadingAnchor, constant: -20),
            closeIconButton.centerYAnchor.constraint(equalTo: titleIcon.centerYAnchor),
            closeIconButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            closeIconButton.widthAnchor.constraint(equalToConstant: 32),
            closeIconButton.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: titleIcon.bottomAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: copyButton.topAnchor, constant: -20),
            copyButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            copyButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            copyButton.widthAnchor.constraint(equalToConstant: 120),
            copyButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            closeButton.widthAnchor.constraint(equalToConstant: 96),
            closeButton.heightAnchor.constraint(equalToConstant: 34)
        ])
        return root
    }

    @objc private func copyDiagnostics(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsReport.pasteboardText(rows: rowsProvider()), forType: .string)
    }

    @objc private func closePanel(_ sender: Any?) {
        close()
    }

    private func diagnosticRowView(_ row: DiagnosticRow, theme: DiagnosticsPanelTheme) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = theme.borderColor.withAlphaComponent(0.45).cgColor
        container.layer?.backgroundColor = theme.rowFill.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let status = NSImageView()
        status.image = NSImage(
            systemSymbolName: row.isOK ? "checkmark.circle" : "exclamationmark.triangle",
            accessibilityDescription: row.isOK ? "OK" : "WARN"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        status.contentTintColor = row.isOK ? theme.okColor : .systemOrange
        status.imageScaling = .scaleNone
        status.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(status)

        let title = NSTextField(labelWithString: row.title)
        title.font = AppFont.semibold(ofSize: 14)
        title.textColor = theme.primaryText
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.borderColor.withAlphaComponent(0.28).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        let detail = NSTextField(labelWithString: row.detail)
        detail.font = .systemFont(ofSize: 14, weight: .regular)
        detail.textColor = theme.secondaryText
        detail.lineBreakMode = .byTruncatingMiddle
        detail.alignment = .right
        detail.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detail)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            status.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 18),
            status.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 150),
            divider.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            divider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 24),
            detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 16),
            detail.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            detail.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func actionButton(title: String, primary: Bool, theme: DiagnosticsPanelTheme, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = primary ? 0 : 1
        button.layer?.backgroundColor = (primary ? theme.primaryButtonBackground : theme.secondaryButtonBackground).cgColor
        button.layer?.borderColor = theme.borderColor.cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: primary ? theme.primaryButtonText : theme.secondaryButtonText
            ]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
