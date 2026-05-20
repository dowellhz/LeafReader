import Cocoa

extension RecentDocumentsPanelController {
    func shelfBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func shelfPrimaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    func shelfSecondaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.45, green: 0.49, blue: 0.60, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark:
            return NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
    }

    func shelfBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.28, green: 0.34, blue: 0.42, alpha: 1)
        }
    }

    func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        ModalOverlayManager.shared.present(panel, attachedTo: parent)
    }

    func confirmShelfAction(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: AppText.cancel)
        alert.applyLeafStyle()
        return alert.runModal() == .alertFirstButtonReturn
    }

    func confirmShelfRemoval() -> ShelfRemovalOptions? {
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
            checkboxWithTitle: AppText.localized("清除 AI 阅读记录", "Clear AI reading records"),
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
        alert.applyLeafStyle()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return ShelfRemovalOptions(
            clearVectorCache: clearVectorCheckbox.state == .on,
            clearWordRecords: clearWordsCheckbox.state == .on,
            clearAIData: clearAIDataCheckbox.state == .on
        )
    }

    func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.reactivatePanelIfNeeded()
        }
    }

    func removeAppActivationObserver() {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    func reactivatePanelIfNeeded() {
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

    func handleDroppedDocumentURLs(_ urls: [URL]) {
        let supported = RecentDocumentsStore.supportedUniqueURLs(urls)
        guard !supported.isEmpty else { return }
        if supported.count == 1 {
            closeThenOpen(path: supported[0].path)
            return
        }
        onImport?(supported)
    }

    @objc func clearRecentDocuments(_ sender: NSButton) {
        onClear?()
        close()
    }

    @objc func openDocumentFromShelf(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        DocumentOpenPanelConfiguration.apply(to: openPanel)
        guard let hostWindow = panel ?? parentWindow ?? NSApp.keyWindow else { return }
        Self.coverLoadQueue.isSuspended = true
        openPanel.beginSheetModal(for: hostWindow) { [weak self] response in
            Self.coverLoadQueue.isSuspended = false
            guard let self, response == .OK, let url = openPanel.url else { return }
            guard ReaderDocumentKind.kind(for: url) != nil else {
                NSSound.beep()
                return
            }
            self.pendingOpenPath = url.path
            self.close()
        }
    }

    @objc func closePanel(_ sender: Any?) {
        close()
    }

    func shelfActionButton(
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

}
