import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers

private final class RecentBookCardView: NSView {
    let path: String
    var onOpen: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onReveal: ((String) -> Void)?
    var onClearVectorCache: ((String) -> Void)?
    var onClearWordRecords: ((String) -> Void)?
    var onClearAIData: ((String) -> Void)?

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

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(menuItem(title: AppText.localized("打开", "Open"), action: #selector(openFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("在 Finder 中显示", "Show in Finder"), action: #selector(revealFromMenu(_:))))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: AppText.localized("移出书架", "Remove from Shelf"), action: #selector(removeFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书向量缓存", "Clear Book Vector Cache"), action: #selector(clearVectorCacheFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书单词记录", "Clear Book Words"), action: #selector(clearWordRecordsFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书 AI 数据", "Clear Book AI Data"), action: #selector(clearAIDataFromMenu(_:))))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openFromMenu(_ sender: NSMenuItem) {
        onOpen?(path)
    }

    @objc private func revealFromMenu(_ sender: NSMenuItem) {
        onReveal?(path)
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        onRemove?(path)
    }

    @objc private func clearVectorCacheFromMenu(_ sender: NSMenuItem) {
        onClearVectorCache?(path)
    }

    @objc private func clearWordRecordsFromMenu(_ sender: NSMenuItem) {
        onClearWordRecords?(path)
    }

    @objc private func clearAIDataFromMenu(_ sender: NSMenuItem) {
        onClearAIData?(path)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class RecentDocumentsDropContentView: NSView {
    var onDroppedDocumentURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ReaderFileDrop.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ReaderFileDrop.perform(sender) { [weak self] urls in
            self?.onDroppedDocumentURLs?(urls)
        }
    }
}

final class RecentDocumentsPanelController: NSObject {
    struct ShelfRemovalOptions {
        let clearVectorCache: Bool
        let clearWordRecords: Bool
        let clearAIData: Bool
    }

    private weak var parentWindow: NSWindow?
    private var panel: NSWindow?
    private var onOpen: ((String) -> Void)?
    private var onClear: (() -> Void)?
    private var onRemoveItem: ((String, ShelfRemovalOptions) -> Void)?
    private var onClearVectorCache: ((String) -> Void)?
    private var onClearWordRecords: ((String) -> Void)?
    private var onClearAIData: ((String) -> Void)?
    private var onImport: (([URL]) -> Void)?
    private var onClose: (() -> Void)?
    private var pendingOpenPath: String?
    private var isClosing = false
    private var appActivationObserver: NSObjectProtocol?

    private let panelSize = NSSize(width: 940, height: 480)
    private let coverSize = NSSize(width: 120, height: 205)
    private static var coverCache: [String: NSImage] = [:]
    private static var placeholderCoverCache: [String: NSImage] = [:]

    deinit {
        removeAppActivationObserver()
    }

    func show(
        items: [RecentDocumentItem],
        attachedTo window: NSWindow?,
        focusPath: String? = nil,
        onOpen: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onRemoveItem: @escaping (String, ShelfRemovalOptions) -> Void,
        onClearVectorCache: @escaping (String) -> Void,
        onClearWordRecords: @escaping (String) -> Void,
        onClearAIData: @escaping (String) -> Void,
        onImport: @escaping ([URL]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onClear = onClear
        self.onRemoveItem = onRemoveItem
        self.onClearVectorCache = onClearVectorCache
        self.onClearWordRecords = onClearWordRecords
        self.onClearAIData = onClearAIData
        self.onImport = onImport
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

        let content = RecentDocumentsDropContentView()
        content.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
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

        let openButton = shelfActionButton(
            title: AppText.localized("增加", "Add"),
            target: self,
            action: #selector(openDocumentFromShelf(_:)),
            panelBackground: panelBackground,
            primaryText: primaryText,
            isDark: isDark
        )
        let clearButton = shelfActionButton(
            title: AppText.localized("清空", "Clear"),
            target: self,
            action: #selector(clearRecentDocuments(_:)),
            panelBackground: panelBackground,
            primaryText: primaryText,
            isDark: isDark
        )

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

        for item in items {
            let card = recentBookCard(for: item, primaryText: primaryText, secondaryText: secondaryText, isDark: isDark)
            card.onOpen = { [weak self] path in
                self?.pendingOpenPath = path
                self?.close()
            }
            card.onReveal = { path in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            card.onRemove = { [weak self] path in
                guard let options = self?.confirmShelfRemoval() else { return }
                self?.onRemoveItem?(path, options)
                if let card = stack.arrangedSubviews.first(where: { ($0 as? RecentBookCardView)?.path == path }) {
                    stack.removeArrangedSubview(card)
                    card.removeFromSuperview()
                }
            }
            card.onClearVectorCache = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书向量缓存？", "Clear Vector Cache for This Book?"),
                    message: AppText.localized("清除后，之后使用文档检索时会重新生成本书向量。", "After clearing, vectors for this book will be regenerated when document retrieval is used."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearVectorCache?(path)
            }
            card.onClearWordRecords = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书单词记录？", "Clear Word Records for This Book?"),
                    message: AppText.localized("这会删除本书已保存的单词、解释和高亮记录。", "This deletes saved words, explanations, and highlights for this book."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearWordRecords?(path)
            }
            card.onClearAIData = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书 AI 数据？", "Clear AI Data for This Book?"),
                    message: AppText.localized("这会删除本书已保存的 AI 对话、来源标注和单词学习记录。", "This deletes saved AI conversations, source marks, and word learning records for this book."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearAIData?(path)
            }
            stack.addArrangedSubview(card)
        }

        for view in [title, closeButton, openButton, clearButton, scrollView] {
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
            openButton.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -10),
            openButton.widthAnchor.constraint(equalToConstant: 68),
            openButton.heightAnchor.constraint(equalToConstant: 28),

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
        installAppActivationObserver()
        showPanel(panel, attachedTo: window)
        if let focusPath {
            DispatchQueue.main.async {
                guard let card = stack.arrangedSubviews
                    .compactMap({ $0 as? RecentBookCardView })
                    .first(where: { $0.path == focusPath }) else { return }
                card.scrollToVisible(card.bounds)
            }
        }
    }

    private func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        ModalOverlayManager.shared.present(panel, attachedTo: parent)
    }

    private func confirmShelfAction(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: AppText.cancel)
        alert.applyLeafWhiteStyle()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmShelfRemoval() -> ShelfRemovalOptions? {
        let alert = NSAlert()
        alert.messageText = AppText.localized("移出书架？", "Remove from Shelf?")
        alert.informativeText = AppText.localized(
            "这会删除这本书的阅读历史，但不会删除原文件。",
            "This removes this book's reading history, but does not delete the original file."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("移出", "Remove"))
        alert.addButton(withTitle: AppText.cancel)

        let clearVectorCheckbox = NSButton(
            checkboxWithTitle: AppText.localized("清除向量", "Clear vector cache"),
            target: nil,
            action: nil
        )
        clearVectorCheckbox.state = .on
        clearVectorCheckbox.font = NSFont.systemFont(ofSize: 13)

        let clearWordsCheckbox = NSButton(
            checkboxWithTitle: AppText.localized("清除单词本", "Clear word book"),
            target: nil,
            action: nil
        )
        clearWordsCheckbox.state = .on
        clearWordsCheckbox.font = NSFont.systemFont(ofSize: 13)

        let clearAIDataCheckbox = NSButton(
            checkboxWithTitle: AppText.localized("清除 AI 数据", "Clear AI data"),
            target: nil,
            action: nil
        )
        clearAIDataCheckbox.state = .on
        clearAIDataCheckbox.font = NSFont.systemFont(ofSize: 13)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 92))
        let stack = NSStackView(views: [clearVectorCheckbox, clearWordsCheckbox, clearAIDataCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: accessory.trailingAnchor),
            stack.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: accessory.bottomAnchor, constant: -6)
        ])
        alert.accessoryView = accessory
        alert.applyLeafWhiteStyle()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return ShelfRemovalOptions(
            clearVectorCache: clearVectorCheckbox.state == .on,
            clearWordRecords: clearWordsCheckbox.state == .on,
            clearAIData: clearAIDataCheckbox.state == .on
        )
    }

    private func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.reactivatePanelIfNeeded()
        }
    }

    private func removeAppActivationObserver() {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    private func reactivatePanelIfNeeded() {
        guard let panel, panel.isVisible else { return }
        ModalOverlayManager.shared.reactivate(panel)
    }

    func close() {
        guard let panel, !isClosing else { return }
        isClosing = true
        removeAppActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: parentWindow)
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

    func closeThenOpen(path: String) {
        pendingOpenPath = path
        close()
    }

    private func handleDroppedDocumentURLs(_ urls: [URL]) {
        let supported = RecentDocumentsStore.supportedUniqueURLs(urls)
        guard !supported.isEmpty else { return }
        if supported.count == 1 {
            closeThenOpen(path: supported[0].path)
            return
        }
        onImport?(supported)
    }

    @objc private func clearRecentDocuments(_ sender: NSButton) {
        onClear?()
        close()
    }

    @objc private func openDocumentFromShelf(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.pdf, .epub, .init(filenameExtension: "docx")].compactMap { $0 }
        openPanel.allowsOtherFileTypes = false
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        guard let hostWindow = panel ?? parentWindow ?? NSApp.keyWindow else { return }
        openPanel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self, response == .OK, let url = openPanel.url else { return }
            self.pendingOpenPath = url.path
            self.close()
        }
    }

    @objc private func closePanel(_ sender: Any?) {
        close()
    }

    private func shelfActionButton(
        title: String,
        target: AnyObject,
        action: Selector,
        panelBackground: NSColor,
        primaryText: NSColor,
        isDark: Bool
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = panelBackground.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = (isDark
            ? NSColor(red: 0.30, green: 0.36, blue: 0.44, alpha: 1)
            : NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1)
        ).cgColor
        button.layer?.cornerRadius = 7
        button.font = AppFont.semibold(ofSize: 13)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppFont.semibold(ofSize: 13),
                .foregroundColor: primaryText
            ]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
        let coverKey = coverCacheKey(for: item)
        if let cachedCover = Self.coverCache[coverKey] {
            cover.image = cachedCover
        } else {
            cover.image = cachedPlaceholderCover(title: displayTitle(for: item), kind: item.kind, isDark: isDark)
            loadCoverImageAsync(for: item, imageView: cover)
        }
        cover.imageScaling = .scaleProportionallyUpOrDown
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

        let progressLabel = NSTextField(labelWithString: progressText(for: item))
        progressLabel.font = AppFont.semibold(ofSize: 11)
        progressLabel.textColor = secondaryText.withAlphaComponent(0.92)
        progressLabel.lineBreakMode = .byTruncatingTail
        progressLabel.maximumNumberOfLines = 1
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [shadowHost, title, subtitle, progressLabel] {
            card.addSubview(view)
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: coverSize.width),
            card.heightAnchor.constraint(equalToConstant: coverSize.height + 104),

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

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            progressLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 5),
            progressLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            progressLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -4)
        ])
        return card
    }

    private func coverCacheKey(for item: RecentDocumentItem) -> String {
        let url = URL(fileURLWithPath: item.path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let digest = SHA256.hash(data: Data("\(item.path)#\(item.kind)#\(ReaderTheme.selected.rawValue)#\(modified)#\(fileSize)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func loadCoverImageAsync(for item: RecentDocumentItem, imageView: NSImageView) {
        let cacheKey = coverCacheKey(for: item)
        let path = item.path
        let kind = item.kind
        let coverSize = self.coverSize
        DispatchQueue.global(qos: .utility).async { [weak imageView] in
            if let diskCover = self.loadDiskCover(cacheKey: cacheKey) {
                DispatchQueue.main.async {
                    Self.coverCache[cacheKey] = diskCover
                    guard let imageView else { return }
                    imageView.image = diskCover
                }
                return
            }

            let url = URL(fileURLWithPath: path)
            if kind == "EPUB" {
                guard let coverData = try? WebDocumentLoader.coverImageData(forEPUB: url),
                      let image = NSImage(data: coverData) else { return }
                image.size = coverSize
                image.cacheMode = .always
                DispatchQueue.main.async {
                    Self.coverCache[cacheKey] = image
                    self.saveDiskCover(image, cacheKey: cacheKey)
                    guard let imageView else { return }
                    imageView.image = image
                }
                return
            }

            guard kind == "PDF" else { return }
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: 0) else { return }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let renderScale = max(2, min(3, scale))
            let targetSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
            let image = page.thumbnail(of: targetSize, for: .cropBox)
            image.size = coverSize
            image.cacheMode = .always
            DispatchQueue.main.async {
                Self.coverCache[cacheKey] = image
                self.saveDiskCover(image, cacheKey: cacheKey)
                guard let imageView else { return }
                imageView.image = image
            }
        }
    }

    private func cachedPlaceholderCover(title: String, kind: String, isDark: Bool) -> NSImage {
        let cacheKey = "\(ReaderTheme.selected.rawValue)#\(kind)#\(title)"
        if let cached = Self.placeholderCoverCache[cacheKey] {
            return cached
        }
        let image = placeholderCover(title: title, kind: kind, isDark: isDark)
        Self.placeholderCoverCache[cacheKey] = image
        return image
    }

    private func loadDiskCover(cacheKey: String) -> NSImage? {
        guard let url = diskCoverURL(cacheKey: cacheKey) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveDiskCover(_ image: NSImage, cacheKey: String) {
        guard let url = diskCoverURL(cacheKey: cacheKey),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func diskCoverURL(cacheKey: String) -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("ShelfCovers", isDirectory: true)
            .appendingPathComponent("\(cacheKey).png")
    }

    private func highResolutionPDFCover(page: PDFPage) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderScale = max(2, min(3, scale))
        let targetSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
        let image = page.thumbnail(of: targetSize, for: .cropBox)
        image.size = coverSize
        image.cacheMode = .always
        return image
    }

    private func placeholderCover(title: String, kind: String, isDark: Bool) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderScale = max(2, min(3, scale))
        let renderSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
        let image = NSImage(size: coverSize)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderSize.width),
            pixelsHigh: Int(renderSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else { return image }
        bitmap.size = coverSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
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
        NSString(string: documentKindText(kind)).draw(in: NSRect(x: 12, y: 18, width: coverSize.width - 24, height: 18), withAttributes: kindAttributes)
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(bitmap)
        return image
    }

    private func displayTitle(for item: RecentDocumentItem) -> String {
        return item.title
    }

    private func displaySubtitle(for item: RecentDocumentItem) -> String {
        documentKindText(item.kind)
    }

    private func documentKindText(_ kind: String) -> String {
        switch kind {
        case "EPUB":
            return AppText.localized("EPUB 书籍", "EPUB Book")
        case "DOCX":
            return AppText.localized("DOCX 文稿", "DOCX Document")
        default:
            return AppText.localized("PDF 书籍", "PDF Book")
        }
    }

    private func progressText(for item: RecentDocumentItem) -> String {
        guard let progress = item.readingProgress else {
            return AppText.localized("未记录进度", "No progress")
        }
        let percent = min(100, max(0, Int((progress * 100).rounded())))
        return AppText.localized("已读 \(percent)%", "\(percent)% read")
    }
}
