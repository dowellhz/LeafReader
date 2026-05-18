import Cocoa
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ReaderWindowController!
    private var helpWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var updateStatusWindow: NSWindow?
    private var updaterController: SPUStandardUpdaterController?
    private var manualUpdateProbeInProgress = false
    private var manualUpdateProbeFoundUpdate = false
    private var manualUpdateProbeHandledResult = false
    private weak var manualUpdateSender: AnyObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller = ReaderWindowController()
        installMainMenu()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openDocument(URL(fileURLWithPath: filename))
        return true
    }

    func refreshMainMenu() {
        installMainMenu()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(settingsMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(navigateMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func appMenuItem() -> NSMenuItem {
        let appName = "Leaf Reader"
        let menu = NSMenu(title: appName)
        menu.addItem(menuItem(
            AppText.localized("关于 \(appName)", "About \(appName)"),
            action: #selector(showAboutLeafReader(_:)),
            key: "",
            target: self
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.settings,
            action: #selector(ReaderWindowController.openAISettings),
            key: ",",
            target: controller
        ))
        menu.addItem(.separator())

        menu.addItem(menuItem(
            AppText.localized("隐藏 \(appName)", "Hide \(appName)"),
            action: #selector(NSApplication.hide(_:)),
            key: "h",
            target: NSApp
        ))
        let hideOthers = menuItem(
            AppText.localized("隐藏其他", "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            target: NSApp
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(menuItem(
            AppText.localized("全部显示", "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            key: "",
            target: NSApp
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("退出 \(appName)", "Quit \(appName)"),
            action: #selector(NSApplication.terminate(_:)),
            key: "q",
            target: NSApp
        ))
        return rootMenuItem(title: appName, submenu: menu)
    }

    private func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.localized("文件", "File"))
        menu.addItem(menuItem(
            AppText.localized("打开...", "Open..."),
            action: #selector(ReaderWindowController.openPDF),
            key: "o",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("书架", "Shelf"),
            action: #selector(ReaderWindowController.showRecentDocuments),
            key: "l",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("关闭窗口", "Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            key: "w",
            target: nil
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    @objc private func showAboutLeafReader(_ sender: Any?) {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.localized("关于 Leaf Reader", "About Leaf Reader")
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = content

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        let nameLabel = NSTextField(labelWithString: "Leaf Reader")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        nameLabel.textColor = .labelColor
        content.addSubview(nameLabel)

        let versionLabel = NSTextField(labelWithString: helpVersionText())
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        versionLabel.textColor = NSColor(red: 0.43, green: 0.47, blue: 0.54, alpha: 1)
        content.addSubview(versionLabel)

        let subtitleLabel = NSTextField(wrappingLabelWithString: AppText.localized("智能文档阅读与学习助手", "Smart document reading and learning assistant"))
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = NSColor(red: 0.43, green: 0.47, blue: 0.54, alpha: 1)
        content.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 82),
            iconView.heightAnchor.constraint(equalToConstant: 82),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            nameLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            versionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28)
        ])

        aboutWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aboutWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func aboutWindowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === aboutWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: aboutWindow)
        aboutWindow = nil
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard let updater = updaterController?.updater else { return }
        guard updater.canCheckForUpdates else {
            showWhiteUpdateStatus(
                title: AppText.localized("正在检查更新", "Checking for Updates"),
                message: AppText.localized("Leaf Reader 正在处理更新，请稍后再试。", "Leaf Reader is already handling an update. Please try again shortly."),
                showsProgress: true
            )
            return
        }

        manualUpdateProbeInProgress = true
        manualUpdateProbeFoundUpdate = false
        manualUpdateProbeHandledResult = false
        manualUpdateSender = sender as AnyObject?
        showWhiteUpdateStatus(
            title: AppText.localized("正在检查更新", "Checking for Updates"),
            message: AppText.localized("正在连接 Leaf Reader 更新源...", "Connecting to the Leaf Reader update feed..."),
            showsProgress: true
        )
        updater.checkForUpdateInformation()
    }

    private func showWhiteUpdateStatus(title: String, message: String, showsProgress: Bool = false) {
        if let updateStatusWindow {
            updateStatusWindow.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.localized("Leaf Reader 更新", "Leaf Reader Updates")
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = content

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor
        content.addSubview(titleLabel)

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = NSColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1)
        messageLabel.maximumNumberOfLines = 3
        content.addSubview(messageLabel)

        let progressIndicator = NSProgressIndicator()
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        if showsProgress {
            progressIndicator.startAnimation(nil)
        }
        progressIndicator.isHidden = !showsProgress
        content.addSubview(progressIndicator)

        let okButton = NSButton(title: "OK", target: self, action: #selector(closeUpdateStatusWindow(_:)))
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.bezelStyle = .rounded
        okButton.font = .systemFont(ofSize: 14, weight: .semibold)
        okButton.keyEquivalent = "\r"
        okButton.isHidden = showsProgress
        content.addSubview(okButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 70),
            iconView.heightAnchor.constraint(equalToConstant: 70),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),

            progressIndicator.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -34),

            okButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            okButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            okButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            okButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        updateStatusWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeUpdateStatusWindow(_ sender: Any?) {
        updateStatusWindow?.close()
    }

    @objc private func updateStatusWindowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === updateStatusWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: updateStatusWindow)
        updateStatusWindow = nil
    }

    private func updateFailureMessage(from error: Error?) -> String {
        guard let nsError = error as NSError? else {
            return AppText.localized("暂时无法检查更新，请稍后再试。", "Unable to check for updates right now. Please try again later.")
        }

        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = nsError.localizedFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let suggestion, !suggestion.isEmpty {
            return "\(description)\n\(suggestion)"
        }
        if let reason, !reason.isEmpty, reason != description {
            return "\(description)\n\(reason)"
        }
        if !description.isEmpty {
            return description
        }
        return AppText.localized("暂时无法检查更新，请检查网络后再试。", "Unable to check for updates. Please check your network connection and try again.")
    }

    private func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.localized("视图", "View"))
        menu.addItem(menuItem(
            AppText.localized("搜索", "Search"),
            action: #selector(ReaderWindowController.showSearchOverlay),
            key: "f",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("背单词", "Vocab"),
            action: #selector(ReaderWindowController.showVocabularyBook),
            key: "d",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("目录", "Table of Contents"),
            action: #selector(ReaderWindowController.showTableOfContents),
            key: "t",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.cover,
            action: #selector(ReaderWindowController.goToCover),
            key: "1",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("显示/隐藏 AI 面板", "Show/Hide AI Panel"),
            action: #selector(ReaderWindowController.toggleAIPanel),
            key: "\\",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("切换单页/双页", "Toggle Single/Two-up"),
            action: #selector(ReaderWindowController.togglePDFPageLayout),
            key: "2",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("放大", "Zoom In"),
            action: #selector(ReaderWindowController.zoomIn),
            key: "+",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("缩小", "Zoom Out"),
            action: #selector(ReaderWindowController.zoomOut),
            key: "-",
            target: controller
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.fullScreen,
            action: #selector(ReaderWindowController.toggleFullScreen),
            key: "f",
            target: controller,
            modifiers: [.command, .control]
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    private func settingsMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.settings)
        menu.addItem(menuItem(
            AppText.localized("基础", "General"),
            action: #selector(ReaderWindowController.openGeneralSettings),
            key: ",",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("模型", "Model"),
            action: #selector(ReaderWindowController.openModelSettings),
            key: "",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("向量", "Vector"),
            action: #selector(ReaderWindowController.openVectorSettings),
            key: "",
            target: controller
        ))
        menu.addItem(menuItem(
            AppText.localized("缓存", "Cache"),
            action: #selector(ReaderWindowController.openCacheSettings),
            key: "",
            target: controller
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    private func navigateMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.localized("导航", "Navigate"))
        menu.addItem(menuItem(
            AppText.prev,
            action: #selector(ReaderWindowController.prevPage),
            key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
            target: controller,
            modifiers: [.command]
        ))
        menu.addItem(menuItem(
            AppText.next,
            action: #selector(ReaderWindowController.nextPage),
            key: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
            target: controller,
            modifiers: [.command]
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    private func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.localized("窗口", "Window"))
        menu.addItem(menuItem(
            AppText.localized("最小化", "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            key: "m",
            target: nil
        ))
        menu.addItem(menuItem(
            AppText.localized("缩放", "Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            key: "",
            target: nil
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            AppText.localized("前置所有窗口", "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            key: "",
            target: NSApp
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    private func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: AppText.localized("帮助", "Help"))
        if updaterController != nil {
            menu.addItem(menuItem(
                AppText.localized("检查更新...", "Check for Updates..."),
                action: #selector(checkForUpdates(_:)),
                key: "",
                target: self
            ))
            menu.addItem(.separator())
        }
        menu.addItem(menuItem(
            AppText.localized("Leaf Reader 帮助", "Leaf Reader Help"),
            action: #selector(showLeafReaderHelp(_:)),
            key: "?",
            target: self,
            modifiers: [.command, .shift]
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
    }

    @objc private func showLeafReaderHelp(_ sender: Any?) {
        if let helpWindow {
            helpWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let title = AppText.localized("Leaf Reader 帮助", "Leaf Reader Help")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.center()

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = contentView

        let pageStack = NSStackView()
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 22
        contentView.addSubview(pageStack)

        let header = NSStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 52

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        header.addArrangedSubview(iconView)

        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 7

        let nameRow = NSStackView()
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 16

        let nameLabel = NSTextField(labelWithString: "Leaf Reader")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(HelpVersionBadgeView(text: helpVersionText()))
        titleStack.addArrangedSubview(nameRow)

        let subtitleLabel = helpTextLabel(
            AppText.localized("您的智能文档阅读与学习助手", "Your smart document reading and learning assistant"),
            size: 18,
            weight: .semibold,
            color: .labelColor
        )
        titleStack.addArrangedSubview(subtitleLabel)

        let descriptionLabel = helpTextLabel(
            AppText.localized(
                "支持多种文档格式，集阅读、AI 问答、背单词于一体，\n让阅读更高效，学习更轻松。",
                "Read multiple document formats with AI Q&A and vocabulary study in one place.\nMake reading more efficient and learning easier."
            ),
            size: 14,
            weight: .regular,
            color: .secondaryLabelColor
        )
        titleStack.addArrangedSubview(descriptionLabel)
        header.addArrangedSubview(titleStack)
        pageStack.addArrangedSubview(header)

        let grid = NSStackView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 14
        let features = helpFeatures()
        for rowFeatures in stride(from: 0, to: features.count, by: 2).map({ Array(features[$0..<min($0 + 2, features.count)]) }) {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 14
            for feature in rowFeatures {
                row.addArrangedSubview(helpCardView(feature))
            }
            grid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }
        pageStack.addArrangedSubview(grid)

        let tip = HelpTipView(text: AppText.localized("你可以通过菜单栏「帮助」或快捷键 ⇧⌘?，随时打开本帮助页面。", "Open this help page any time from the Help menu or with Shift-Command-?."))
        tip.translatesAutoresizingMaskIntoConstraints = false
        pageStack.addArrangedSubview(tip)

        NSLayoutConstraint.activate([
            pageStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 38),
            pageStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 72),
            pageStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -72),
            pageStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),

            header.leadingAnchor.constraint(equalTo: pageStack.leadingAnchor, constant: 98),
            header.trailingAnchor.constraint(lessThanOrEqualTo: pageStack.trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 104),
            iconView.heightAnchor.constraint(equalToConstant: 104),

            grid.leadingAnchor.constraint(equalTo: pageStack.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: pageStack.trailingAnchor),
            grid.widthAnchor.constraint(equalTo: pageStack.widthAnchor),

            tip.leadingAnchor.constraint(equalTo: pageStack.leadingAnchor),
            tip.trailingAnchor.constraint(equalTo: pageStack.trailingAnchor),
            tip.heightAnchor.constraint(equalToConstant: 56)
        ])

        helpWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(helpWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeLeafReaderHelp(_ sender: Any?) {
        helpWindow?.close()
    }

    @objc private func helpWindowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === helpWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: helpWindow)
        helpWindow = nil
    }

    private func helpVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let displayVersion = version?.isEmpty == false ? version! : "1.0"
        return AppText.localized("版本 \(displayVersion)", "Version \(displayVersion)")
    }

    private struct HelpFeature {
        let title: String
        let items: [String]
        let icon: HelpFeatureIcon
    }

    private func helpFeatures() -> [HelpFeature] {
        [
            HelpFeature(
                title: AppText.localized("阅读", "Reading"),
                items: [
                    AppText.localized("打开 PDF、EPUB、DOCX 或 TXT 文件。", "Open PDF, EPUB, DOCX, or TXT files."),
                    AppText.localized("支持单双页、缩放、全屏和搜索。", "Single-page, two-up layout, zoom, full screen, and search are supported."),
                    AppText.localized("拖入一本书会直接打开；拖入多本书会进入书架，并把相关书放到前面。", "Dropping one book opens it directly; dropping multiple books opens the shelf and moves related books to the front.")
                ],
                icon: .reading
            ),
            HelpFeature(
                title: AppText.localized("AI 问答", "AI Q&A"),
                items: [
                    AppText.localized("选中文本后可以让 AI 总结、翻译或继续追问。", "Select text to summarize, translate, or ask follow-up questions with AI."),
                    AppText.localized("AI 回答会和当前页或选中文本关联，点击文本标注可以定位到对应 AI 气泡。", "AI answers are linked to the current page or selected text; click the text annotation to locate the related AI bubble."),
                    AppText.localized("如果关闭保存 AI 对话，再次打开时不会恢复历史对话和对应标注。", "If AI conversation saving is disabled, previous conversations and their annotations are not restored.")
                ],
                icon: .qa
            ),
            HelpFeature(
                title: AppText.localized("背单词", "Vocabulary"),
                items: [
                    AppText.localized("选中或点击单词后可以加入本书单词本。", "Select or click a word to add it to the current book's vocabulary list."),
                    AppText.localized("背单词用于按本书学习进度复习；复习、新词、全部分别显示今天复习过、今天新增和本书全部单词。", "Use Study to review words by this book's progress; Review, New, and All list today's reviewed words, today's new words, and all words in the book."),
                    AppText.localized("单词列表支持导出 Markdown 和 Anki CSV。", "Vocabulary lists can be exported as Markdown or Anki CSV.")
                ],
                icon: .vocabulary
            ),
            HelpFeature(
                title: AppText.localized("书架", "Shelf"),
                items: [
                    AppText.localized("管理你导入的所有书籍，支持搜索、排序，并可快速进入阅读。", "Manage imported books with search and sorting, then jump back into reading quickly.")
                ],
                icon: .shelf
            )
        ]
    }

    private func helpCardView(_ feature: HelpFeature) -> NSView {
        let card = HelpCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 18
        card.addSubview(content)

        let iconView = HelpFeatureIconView(icon: feature.icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(iconView)

        let copyStack = NSStackView()
        copyStack.translatesAutoresizingMaskIntoConstraints = false
        copyStack.orientation = .vertical
        copyStack.alignment = .leading
        copyStack.spacing = 12

        let titleLabel = helpTextLabel(feature.title, size: 18, weight: .semibold, color: .labelColor)
        copyStack.addArrangedSubview(titleLabel)

        let bulletStack = NSStackView()
        bulletStack.translatesAutoresizingMaskIntoConstraints = false
        bulletStack.orientation = .vertical
        bulletStack.alignment = .leading
        bulletStack.spacing = 7
        for item in feature.items {
            bulletStack.addArrangedSubview(helpBulletRow(item))
        }
        copyStack.addArrangedSubview(bulletStack)
        content.addArrangedSubview(copyStack)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 152),
            iconView.widthAnchor.constraint(equalToConstant: 66),
            iconView.heightAnchor.constraint(equalToConstant: 66),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            content.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func helpTextLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func helpBulletRow(_ text: String) -> NSView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8

        let bullet = NSTextField(labelWithString: "•")
        bullet.translatesAutoresizingMaskIntoConstraints = false
        bullet.font = .systemFont(ofSize: 14, weight: .medium)
        bullet.textColor = .labelColor

        let label = helpTextLabel(text, size: 13.5, weight: .regular, color: .labelColor)
        row.addArrangedSubview(bullet)
        row.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            bullet.widthAnchor.constraint(equalToConstant: 12)
        ])
        return row
    }

    private func rootMenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func menuItem(
        _ title: String,
        action: Selector?,
        key: String,
        target: AnyObject?,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}

private enum HelpFeatureIcon {
    case reading
    case qa
    case vocabulary
    case shelf

    var foreground: NSColor {
        switch self {
        case .reading: return NSColor(calibratedRed: 0.25, green: 0.70, blue: 0.15, alpha: 1)
        case .qa: return NSColor(calibratedRed: 0.45, green: 0.24, blue: 0.78, alpha: 1)
        case .vocabulary: return NSColor(calibratedRed: 0.09, green: 0.45, blue: 0.98, alpha: 1)
        case .shelf: return NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.00, alpha: 1)
        }
    }

    var background: NSColor {
        switch self {
        case .reading: return NSColor(calibratedRed: 0.88, green: 0.97, blue: 0.85, alpha: 1)
        case .qa: return NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.98, alpha: 1)
        case .vocabulary: return NSColor(calibratedRed: 0.86, green: 0.93, blue: 1.00, alpha: 1)
        case .shelf: return NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.83, alpha: 1)
        }
    }
}

private final class HelpCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class HelpVersionBadgeView: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.90, green: 0.99, blue: 0.89, alpha: 1).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.25, green: 0.74, blue: 0.27, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.17, green: 0.63, blue: 0.18, alpha: 1)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class HelpTipView: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.93, green: 1.00, blue: 0.96, alpha: 0.78).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.55, green: 0.86, blue: 0.66, alpha: 0.85).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6

        let icon = HelpLeafIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: AppText.localized("小贴士", "Tip"))
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        addSubview(title)

        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 11),

            label.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class HelpFeatureIconView: NSView {
    private let icon: HelpFeatureIcon

    init(icon: HelpFeatureIcon) {
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = bounds.insetBy(dx: 0, dy: 0)
        icon.background.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        if icon == .vocabulary {
            drawLetter(in: bounds.insetBy(dx: 15, dy: 14))
            return
        }

        guard let gradient = NSGradient(starting: icon.foreground.withAlphaComponent(0.88), ending: icon.foreground) else {
            icon.foreground.setFill()
            drawSymbol(in: bounds.insetBy(dx: 16, dy: 16))
            return
        }
        NSGraphicsContext.saveGraphicsState()
        drawSymbolClip(in: bounds.insetBy(dx: 16, dy: 16))
        gradient.draw(in: bounds, angle: -35)
        NSGraphicsContext.restoreGraphicsState()
        drawSymbolDetails(in: bounds.insetBy(dx: 16, dy: 16))
    }

    private func drawSymbolClip(in rect: NSRect) {
        let path = symbolPath(in: rect)
        path.addClip()
    }

    private func drawSymbol(in rect: NSRect) {
        symbolPath(in: rect).fill()
    }

    private func symbolPath(in rect: NSRect) -> NSBezierPath {
        switch icon {
        case .reading:
            return bookPath(in: rect)
        case .qa:
            return bubblePath(in: rect)
        case .vocabulary:
            return letterPath(in: rect)
        case .shelf:
            return shelfPath(in: rect)
        }
    }

    private func bookPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let gap: CGFloat = rect.width * 0.08
        let pageWidth = (rect.width - gap) / 2
        let left = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.06, width: pageWidth, height: rect.height * 0.88)
        let right = NSRect(x: rect.minX + pageWidth + gap, y: left.minY, width: pageWidth, height: left.height)
        path.append(NSBezierPath(roundedRect: left, xRadius: 7, yRadius: 7))
        path.append(NSBezierPath(roundedRect: right, xRadius: 7, yRadius: 7))
        return path
    }

    private func bubblePath(in rect: NSRect) -> NSBezierPath {
        let bubbleRect = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.23, width: rect.width, height: rect.height * 0.68)
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 12, yRadius: 12)
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.26, y: bubbleRect.minY + 2))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.15, y: bubbleRect.minY + rect.height * 0.22))
        path.close()
        return path
    }

    private func letterPath(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(rect: rect)
    }

    private func shelfPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let base = NSRect(x: rect.minX - 1, y: rect.minY + 1, width: rect.width + 2, height: 6)
        path.append(NSBezierPath(roundedRect: base, xRadius: 3, yRadius: 3))

        let bookWidth = rect.width * 0.24
        let bookRects = [
            NSRect(x: rect.minX + rect.width * 0.08, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.62),
            NSRect(x: rect.midX - bookWidth / 2, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.82),
            NSRect(x: rect.maxX - rect.width * 0.08 - bookWidth, y: rect.minY + 8, width: bookWidth, height: rect.height * 0.68)
        ]
        for book in bookRects {
            path.append(NSBezierPath(roundedRect: book, xRadius: 3, yRadius: 3))
            path.append(NSBezierPath(roundedRect: NSRect(x: book.midX - 2.5, y: book.maxY - book.height * 0.48, width: 5, height: book.height * 0.28), xRadius: 2.5, yRadius: 2.5))
            path.append(NSBezierPath(roundedRect: NSRect(x: book.minX + 2, y: book.minY + 9, width: book.width - 4, height: 2.5), xRadius: 1.25, yRadius: 1.25))
        }
        return path
    }

    private func drawLetter(in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: rect.height * 1.2, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: icon.foreground
        ]
        let size = ("A" as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * 0.03)
        ("A" as NSString).draw(at: point, withAttributes: attributes)
    }

    private func drawSymbolDetails(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.88).setFill()
        switch icon {
        case .reading:
            let columnWidth = rect.width * 0.11
            let columnHeight = rect.height * 0.48
            let y = rect.midY - columnHeight / 2
            NSBezierPath(roundedRect: NSRect(x: rect.minX + rect.width * 0.23, y: y, width: columnWidth, height: columnHeight), xRadius: columnWidth / 2, yRadius: columnWidth / 2).fill()
            NSBezierPath(roundedRect: NSRect(x: rect.maxX - rect.width * 0.23 - columnWidth, y: y, width: columnWidth, height: columnHeight), xRadius: columnWidth / 2, yRadius: columnWidth / 2).fill()
        case .qa:
            let radius = rect.width * 0.075
            for index in 0..<3 {
                let x = rect.midX - radius * 3.2 + CGFloat(index) * radius * 3.2
                NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - radius * 0.2, width: radius * 2, height: radius * 2)).fill()
            }
        case .shelf:
            for x in [rect.minX + rect.width * 0.20, rect.midX, rect.maxX - rect.width * 0.20] {
                NSBezierPath(roundedRect: NSRect(x: x - 2.3, y: rect.minY + rect.height * 0.50, width: 4.6, height: rect.height * 0.22), xRadius: 2.3, yRadius: 2.3).fill()
            }
            for y in [rect.minY + 13, rect.minY + 18] {
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 5, y: y, width: rect.width - 10, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            }
        case .vocabulary:
            break
        }
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard manualUpdateProbeInProgress else { return }
        manualUpdateProbeFoundUpdate = true
        manualUpdateProbeHandledResult = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard manualUpdateProbeInProgress, !manualUpdateProbeFoundUpdate else { return }
        manualUpdateProbeHandledResult = true
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? helpVersionText()
        showWhiteUpdateStatus(
            title: AppText.localized("已是最新版本", "You're up to date!"),
            message: AppText.localized(
                "Leaf Reader \(version) 已是当前最新版本。",
                "Leaf Reader \(version) is currently the newest version available."
            )
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualUpdateProbeInProgress else { return }

        let shouldPresentUpdate = manualUpdateProbeFoundUpdate
        let shouldShowError = !manualUpdateProbeHandledResult && error != nil

        manualUpdateProbeInProgress = false
        manualUpdateProbeFoundUpdate = false
        manualUpdateProbeHandledResult = false
        let sender = manualUpdateSender
        manualUpdateSender = nil

        if shouldPresentUpdate {
            updateStatusWindow?.close()
            DispatchQueue.main.async { [weak self] in
                self?.updaterController?.checkForUpdates(sender)
            }
        } else if shouldShowError {
            showWhiteUpdateStatus(
                title: AppText.localized("检查更新失败", "Update Check Failed"),
                message: updateFailureMessage(from: error)
            )
        }
    }
}

private final class HelpLeafIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let green = NSColor(calibratedRed: 0.19, green: 0.68, blue: 0.31, alpha: 1)
        green.setStroke()
        green.setFill()

        let leafRect = bounds.insetBy(dx: 5, dy: 4)
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: leafRect.minX + leafRect.width * 0.15, y: leafRect.minY + leafRect.height * 0.34))
        leaf.curve(
            to: NSPoint(x: leafRect.maxX, y: leafRect.maxY),
            controlPoint1: NSPoint(x: leafRect.minX + leafRect.width * 0.18, y: leafRect.maxY),
            controlPoint2: NSPoint(x: leafRect.maxX * 0.86, y: leafRect.maxY * 0.98)
        )
        leaf.curve(
            to: NSPoint(x: leafRect.minX + leafRect.width * 0.15, y: leafRect.minY + leafRect.height * 0.34),
            controlPoint1: NSPoint(x: leafRect.maxX * 0.93, y: leafRect.minY + leafRect.height * 0.18),
            controlPoint2: NSPoint(x: leafRect.minX + leafRect.width * 0.38, y: leafRect.minY + leafRect.height * 0.02)
        )
        leaf.lineWidth = 2
        leaf.stroke()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: bounds.minX + 5, y: bounds.minY + 4))
        stem.curve(
            to: NSPoint(x: leafRect.maxX - 2, y: leafRect.maxY - 2),
            controlPoint1: NSPoint(x: leafRect.minX + leafRect.width * 0.32, y: leafRect.minY + leafRect.height * 0.42),
            controlPoint2: NSPoint(x: leafRect.minX + leafRect.width * 0.62, y: leafRect.minY + leafRect.height * 0.68)
        )
        stem.lineWidth = 2
        stem.stroke()
    }
}
