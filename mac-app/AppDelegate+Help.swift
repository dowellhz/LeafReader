import Cocoa
import Sparkle

private struct HelpFeature {
    let title: String
    let items: [String]
    let icon: HelpFeatureIcon
}

extension AppDelegate {
    @objc func showLeafReaderHelp(_ sender: Any?) {
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

        let theme = ReaderTheme.selected
        let backgroundColor: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        switch theme {
        case .original:
            backgroundColor = .white
            primaryText = .labelColor
            secondaryText = .secondaryLabelColor
        case .eyeCare:
            backgroundColor = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
            secondaryText = NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark:
            backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            secondaryText = NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = backgroundColor.cgColor
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
        nameLabel.textColor = primaryText
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(HelpVersionBadgeView(text: helpVersionText()))
        titleStack.addArrangedSubview(nameRow)

        let subtitleLabel = helpTextLabel(
            AppText.localized("您的智能文档阅读与学习助手", "Your smart document reading and learning assistant"),
            size: 18,
            weight: .semibold,
            color: primaryText
        )
        titleStack.addArrangedSubview(subtitleLabel)

        let descriptionLabel = helpTextLabel(
            AppText.localized(
                "支持多种文档格式，集阅读、AI 问答、背单词于一体，\n让阅读更高效，学习更轻松。",
                "Read multiple document formats with AI Q&A and vocabulary study in one place.\nMake reading more efficient and learning easier."
            ),
            size: 14,
            weight: .regular,
            color: secondaryText
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

    func helpVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let displayVersion = version?.isEmpty == false ? version! : "1.0"
        return AppText.localized("版本 \(displayVersion)", "Version \(displayVersion)")
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

}
