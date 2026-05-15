import Cocoa

final class RecentDocumentsPanelController: NSObject {
    private weak var parentWindow: NSWindow?
    private var panel: NSWindow?
    private var onOpen: ((String) -> Void)?
    private var onClear: (() -> Void)?
    private var onClose: (() -> Void)?
    private var pendingOpenPath: String?
    private var isClosing = false

    func show(
        items: [RecentDocumentItem],
        attachedTo window: NSWindow?,
        onOpen: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onClear = onClear
        self.onClose = onClose
        self.parentWindow = window

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let isDark = ReaderTheme.selected == .dark
        let panelBackground = isDark
            ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor.white
        let primaryText = isDark
            ? NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        panel.backgroundColor = .clear
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = isDark ? 1 : 0
        content.layer?.borderColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1).cgColor
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.18
        content.layer?.shadowRadius = 24
        content.layer?.shadowOffset = CGSize(width: 0, height: -8)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let title = NSTextField(labelWithString: AppText.localized("最近阅读", "Recent Reading"))
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.textColor = primaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "", target: self, action: #selector(closePanel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: AppText.localized("清空", "Clear"), target: self, action: #selector(clearRecentDocuments(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .regular
        clearButton.font = NSFont.systemFont(ofSize: 13)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for item in items {
            let row = recentDocumentRow(for: item)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
        }

        for view in [title, closeButton, clearButton, scrollView] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 52),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            clearButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            clearButton.widthAnchor.constraint(equalToConstant: 76),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 52),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -52),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -30),

            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        self.panel = panel
        showPanel(panel, attachedTo: window)
    }

    private func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        if let parent {
            let parentFrame = parent.frame
            let origin = NSPoint(
                x: parentFrame.midX - panel.frame.width / 2,
                y: parentFrame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard let panel, !isClosing else { return }
        isClosing = true
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        let openPath = pendingOpenPath
        pendingOpenPath = nil
        self.panel = nil
        isClosing = false
        let onClose = self.onClose
        let onOpen = self.onOpen
        DispatchQueue.main.async {
            onClose?()
            if let openPath {
                onOpen?(openPath)
            }
        }
    }

    @objc private func openRecentDocumentFromButton(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        pendingOpenPath = path
        close()
    }

    @objc private func clearRecentDocuments(_ sender: NSButton) {
        onClear?()
        close()
    }

    @objc private func closePanel(_ sender: Any?) {
        close()
    }

    private func recentDocumentRow(for item: RecentDocumentItem) -> NSView {
        let isDark = ReaderTheme.selected == .dark
        let primaryText = isDark
            ? NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        let secondaryText = isDark
            ? NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
            : NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
            : NSColor(red: 0.975, green: 0.98, blue: 0.988, alpha: 1)
        ).cgColor
        row.layer?.borderWidth = isDark ? 1 : 0
        row.layer?.borderColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1).cgColor
        row.layer?.cornerRadius = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: iconName(forRecentKind: item.kind), accessibilityDescription: item.kind)
        icon.contentTintColor = secondaryText
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: item.title)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = primaryText
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "\(item.kind)  ·  \(URL(fileURLWithPath: item.path).deletingLastPathComponent().path)")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = secondaryText
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let openButton = NSButton(title: AppText.localized("打开", "Open"), target: self, action: #selector(openRecentDocumentFromButton(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .regular
        openButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        openButton.identifier = NSUserInterfaceItemIdentifier(item.path)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [icon, title, subtitle, openButton] {
            row.addSubview(view)
        }

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 70),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -18),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            openButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
            openButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 82)
        ])
        return row
    }

    private func iconName(forRecentKind kind: String) -> String {
        switch kind {
        case "EPUB":
            return "book.closed"
        case "DOCX":
            return "doc.text"
        default:
            return "doc.richtext"
        }
    }
}
