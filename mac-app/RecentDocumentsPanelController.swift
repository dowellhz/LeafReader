import Cocoa
import PDFKit

private final class RecentBookCardView: NSView {
    let path: String
    var onOpen: ((String) -> Void)?

    init(path: String) {
        self.path = path
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        path = ""
        super.init(coder: coder)
    }

    override func mouseUp(with event: NSEvent) {
        onOpen?(path)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class RecentDocumentsPanelController: NSObject {
    private weak var parentWindow: NSWindow?
    private var panel: NSWindow?
    private var onOpen: ((String) -> Void)?
    private var onClear: (() -> Void)?
    private var onClose: (() -> Void)?
    private var pendingOpenPath: String?
    private var isClosing = false

    private let panelSize = NSSize(width: 940, height: 430)
    private let coverSize = NSSize(width: 120, height: 205)

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
            contentRect: NSRect(origin: .zero, size: panelSize),
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
            : NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        let secondaryText = isDark
            ? NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
            : NSColor(red: 0.45, green: 0.49, blue: 0.60, alpha: 1)

        panel.backgroundColor = .clear
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = 1
        content.layer?.borderColor = (isDark
            ? NSColor(red: 0.28, green: 0.34, blue: 0.42, alpha: 1)
            : NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
        ).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        content.layer?.shadowRadius = 32
        content.layer?.shadowOffset = CGSize(width: 0, height: -12)
        content.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = content

        let title = NSTextField(labelWithString: AppText.localized("书架", "Shelf"))
        title.font = AppFont.semibold(ofSize: 22)
        title.textColor = primaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "", target: self, action: #selector(closePanel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: AppText.localized("清空", "Clear"), target: self, action: #selector(clearRecentDocuments(_:)))
        clearButton.isBordered = false
        clearButton.wantsLayer = true
        clearButton.layer?.backgroundColor = panelBackground.cgColor
        clearButton.layer?.borderWidth = 1
        clearButton.layer?.borderColor = (isDark
            ? NSColor(red: 0.30, green: 0.36, blue: 0.44, alpha: 1)
            : NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1)
        ).cgColor
        clearButton.layer?.cornerRadius = 7
        clearButton.font = AppFont.semibold(ofSize: 13)
        clearButton.attributedTitle = NSAttributedString(
            string: clearButton.title,
            attributes: [
                .font: AppFont.semibold(ofSize: 13),
                .foregroundColor: primaryText
            ]
        )
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 28
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for item in items.prefix(24) {
            let card = recentBookCard(for: item, primaryText: primaryText, secondaryText: secondaryText, isDark: isDark)
            card.onOpen = { [weak self] path in
                self?.pendingOpenPath = path
                self?.close()
            }
            stack.addArrangedSubview(card)
        }

        for view in [title, closeButton, clearButton, scrollView] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            clearButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -22),
            clearButton.widthAnchor.constraint(equalToConstant: 68),
            clearButton.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 38),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -42),

            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])

        self.panel = panel
        showPanel(panel, attachedTo: window)
    }

    private func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        if let parent {
            let parentFrame = parent.frame
            let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let origin = NSPoint(
                x: parentFrame.midX - panel.frame.width / 2,
                y: parentFrame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(clampedOrigin(origin, panelSize: panel.frame.size, visibleFrame: visibleFrame))
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect?) -> NSPoint {
        guard let visibleFrame else { return origin }
        let minX = visibleFrame.minX + 12
        let maxX = visibleFrame.maxX - panelSize.width - 12
        let minY = visibleFrame.minY + 12
        let maxY = visibleFrame.maxY - panelSize.height - 12
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
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

    @objc private func clearRecentDocuments(_ sender: NSButton) {
        onClear?()
        close()
    }

    @objc private func closePanel(_ sender: Any?) {
        close()
    }

    private func recentBookCard(
        for item: RecentDocumentItem,
        primaryText: NSColor,
        secondaryText: NSColor,
        isDark: Bool
    ) -> RecentBookCardView {
        let card = RecentBookCardView(path: item.path)
        card.translatesAutoresizingMaskIntoConstraints = false

        let cover = NSImageView()
        cover.image = coverImage(for: item, isDark: isDark)
        cover.imageScaling = .scaleAxesIndependently
        cover.wantsLayer = true
        cover.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.985, alpha: 1)
        ).cgColor
        cover.layer?.cornerRadius = 4
        cover.layer?.masksToBounds = true
        cover.layer?.borderWidth = 0.5
        cover.layer?.borderColor = NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.08).cgColor
        cover.translatesAutoresizingMaskIntoConstraints = false

        let shadowHost = NSView()
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = isDark ? 0.32 : 0.20
        shadowHost.layer?.shadowRadius = 9
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -4)
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.addSubview(cover)

        let title = NSTextField(labelWithString: displayTitle(for: item))
        title.font = AppFont.semibold(ofSize: 13)
        title.textColor = primaryText
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: displaySubtitle(for: item))
        subtitle.font = AppFont.semibold(ofSize: 12)
        subtitle.textColor = secondaryText
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        for view in [shadowHost, title, subtitle] {
            card.addSubview(view)
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: coverSize.width),
            card.heightAnchor.constraint(equalToConstant: coverSize.height + 60),

            shadowHost.topAnchor.constraint(equalTo: card.topAnchor),
            shadowHost.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shadowHost.widthAnchor.constraint(equalToConstant: coverSize.width),
            shadowHost.heightAnchor.constraint(equalToConstant: coverSize.height),
            cover.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            cover.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),

            title.topAnchor.constraint(equalTo: shadowHost.bottomAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
        return card
    }

    private func coverImage(for item: RecentDocumentItem, isDark: Bool) -> NSImage {
        let url = URL(fileURLWithPath: item.path)
        if item.kind == "PDF",
           let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            return page.thumbnail(of: coverSize, for: .cropBox)
        }
        return placeholderCover(title: displayTitle(for: item), kind: item.kind, isDark: isDark)
    }

    private func placeholderCover(title: String, kind: String, isDark: Bool) -> NSImage {
        let image = NSImage(size: coverSize)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: coverSize)
        let background = isDark
            ? NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            : NSColor.white
        background.setFill()
        rect.fill()
        (isDark
            ? NSColor(red: 0.28, green: 0.32, blue: 0.39, alpha: 1)
            : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        ).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13),
            .foregroundColor: isDark ? NSColor.white : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let kindAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 9),
            .foregroundColor: isDark ? NSColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 1) : NSColor(red: 0.35, green: 0.39, blue: 0.48, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let trimmedTitle = title.count > 34 ? String(title.prefix(34)) : title
        NSString(string: trimmedTitle).draw(in: NSRect(x: 14, y: coverSize.height * 0.48, width: coverSize.width - 28, height: 54), withAttributes: titleAttributes)
        NSString(string: "\(kind) 文档").draw(in: NSRect(x: 12, y: 18, width: coverSize.width - 24, height: 18), withAttributes: kindAttributes)
        image.unlockFocus()
        return image
    }

    private func displayTitle(for item: RecentDocumentItem) -> String {
        if item.kind == "PDF",
           let title = PDFDocument(url: URL(fileURLWithPath: item.path))?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return item.title
    }

    private func displaySubtitle(for item: RecentDocumentItem) -> String {
        if item.kind == "PDF",
           let author = PDFDocument(url: URL(fileURLWithPath: item.path))?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
           !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return author.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch item.kind {
        case "EPUB":
            return "EPUB 文档"
        case "DOCX":
            return "DOCX 文档"
        default:
            return "PDF 文档"
        }
    }
}
