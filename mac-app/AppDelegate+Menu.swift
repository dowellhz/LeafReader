import Cocoa
import Sparkle

extension AppDelegate {
    func refreshMainMenu() {
        installMainMenu()
    }

    func installMainMenu() {
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
        if updaterController != nil {
            menu.addItem(menuItem(
                AppText.localized("检查更新...", "Check for Updates..."),
                action: #selector(checkForUpdates(_:)),
                key: "",
                target: self
            ))
        }
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
        menu.addItem(menuItem(
            AppText.localized("适合宽度", "Fit Width"),
            action: #selector(ReaderWindowController.fitPDFToWidth),
            key: "0",
            target: controller,
            modifiers: [.command]
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
            AppText.localized("AI 分析", "AI Analysis"),
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
        menu.addItem(menuItem(
            AppText.localized("Leaf Reader 帮助", "Leaf Reader Help"),
            action: #selector(showLeafReaderHelp(_:)),
            key: "?",
            target: self,
            modifiers: [.command, .shift]
        ))
        return rootMenuItem(title: menu.title, submenu: menu)
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
    }}
