import Cocoa

struct AISettingsCacheSection {
    let cacheStatusLabel: NSTextField
    let currentIndexStatusLabel: NSTextField
    let pageViews: [NSView]

    fileprivate let currentIndexCard: NSView
    fileprivate let vectorCacheCard: NSView
    fileprivate let currentIndexLabel: NSTextField
    fileprivate let startIndexButton: NSButton
    fileprivate let pauseIndexButton: NSButton
    fileprivate let cancelIndexButton: NSButton
    fileprivate let clearCurrentIndexButton: NSButton
    fileprivate let clearCurrentWordsButton: NSButton
    fileprivate let cacheLabel: NSTextField
    fileprivate let cacheDisclosureButton: NSButton
    fileprivate let clearVectorCacheButton: NSButton
}

extension AISettingsPanelController {
    func makeCacheSection(
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor
    ) -> AISettingsCacheSection {
        let cacheLabel = label(AppText.localized("AI 分析缓存", "AI Analysis Cache"), size: 15, weight: .semibold, color: primaryText)
        let cacheStatusLabel = label(AppText.localized("正在统计缓存...", "Calculating cache..."), size: settingsFontSize, color: secondaryText)
        let cacheDisclosureButton = NSButton(title: "", target: self, action: #selector(clearVectorCache(_:)))
        cacheDisclosureButton.isBordered = false
        cacheDisclosureButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        cacheDisclosureButton.contentTintColor = primaryText
        cacheDisclosureButton.isHidden = true
        cacheDisclosureButton.translatesAutoresizingMaskIntoConstraints = false
        let clearVectorCacheButton = cacheActionButton(
            title: AppText.localized("清除全部缓存", "Clear All Cache"),
            symbol: "trash",
            tint: NSColor(red: 1.00, green: 0.16, blue: 0.18, alpha: 1),
            target: self,
            action: #selector(clearVectorCache(_:))
        )
        clearVectorCacheButton.layer?.cornerRadius = 8
        clearVectorCacheButton.font = AppFont.semibold(ofSize: 14)
        clearVectorCacheButton.attributedTitle = NSAttributedString(
            string: AppText.localized("清除全部缓存", "Clear All Cache"),
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: primaryText
            ]
        )

        let currentIndexLabel = label(AppText.localized("当前书 AI 分析数据", "Current Book AI Analysis Data"), size: 15, weight: .semibold, color: primaryText)
        let currentIndexStatusLabel = label(currentVectorIndexStatus?() ?? AppText.noPDF, size: settingsFontSize, color: secondaryText)
        currentIndexStatusLabel.maximumNumberOfLines = 2
        currentIndexStatusLabel.lineBreakMode = .byWordWrapping
        let startIndexButton = cacheActionButton(
            title: AppText.localized("生成/更新本书缓存", "Build / Update Book Cache"),
            symbol: "play.circle",
            tint: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),
            target: self,
            action: #selector(startCurrentVectorIndex(_:))
        )
        let pauseIndexButton = cacheActionButton(
            title: AppText.localized("暂停/继续", "Pause / Resume"),
            symbol: "pause.circle",
            tint: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
            target: self,
            action: #selector(toggleCurrentVectorIndex(_:))
        )
        let cancelIndexButton = cacheActionButton(
            title: AppText.localized("取消分析", "Cancel"),
            symbol: "minus.circle",
            tint: NSColor(red: 1.00, green: 0.22, blue: 0.28, alpha: 1),
            target: self,
            action: #selector(cancelCurrentVectorIndex(_:))
        )
        let clearCurrentIndexButton = cacheActionButton(
            title: AppText.localized("清除本书分析缓存", "Clear Book Analysis Cache"),
            symbol: "paintbrush",
            tint: NSColor(red: 0.60, green: 0.27, blue: 1.00, alpha: 1),
            target: self,
            action: #selector(clearCurrentVectorIndex(_:))
        )
        let clearCurrentWordsButton = cacheActionButton(
            title: AppText.localized("清除本书单词记录", "Clear Book Words"),
            symbol: "trash",
            tint: NSColor(red: 0.00, green: 0.72, blue: 0.74, alpha: 1),
            target: self,
            action: #selector(clearCurrentWordRecords(_:))
        )
        let currentIndexCard = settingsCard()
        let vectorCacheCard = settingsCard()
        for card in [currentIndexCard, vectorCacheCard] {
            card.layer?.backgroundColor = NSColor.clear.cgColor
            card.layer?.borderWidth = 0
        }

        for view in [currentIndexLabel, startIndexButton, pauseIndexButton, cancelIndexButton, clearCurrentIndexButton, clearCurrentWordsButton] {
            currentIndexCard.addSubview(view)
        }
        for view in [cacheLabel, cacheStatusLabel, cacheDisclosureButton, clearVectorCacheButton] {
            vectorCacheCard.addSubview(view)
        }

        return AISettingsCacheSection(
            cacheStatusLabel: cacheStatusLabel,
            currentIndexStatusLabel: currentIndexStatusLabel,
            pageViews: [currentIndexCard, vectorCacheCard],
            currentIndexCard: currentIndexCard,
            vectorCacheCard: vectorCacheCard,
            currentIndexLabel: currentIndexLabel,
            startIndexButton: startIndexButton,
            pauseIndexButton: pauseIndexButton,
            cancelIndexButton: cancelIndexButton,
            clearCurrentIndexButton: clearCurrentIndexButton,
            clearCurrentWordsButton: clearCurrentWordsButton,
            cacheLabel: cacheLabel,
            cacheDisclosureButton: cacheDisclosureButton,
            clearVectorCacheButton: clearVectorCacheButton
        )
    }

    func cacheConstraints(
        for section: AISettingsCacheSection,
        page: NSView,
        formWidth: CGFloat
    ) -> [NSLayoutConstraint] {
        [
            section.currentIndexCard.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.currentIndexCard.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.currentIndexCard.widthAnchor.constraint(equalToConstant: formWidth),
            section.currentIndexCard.heightAnchor.constraint(equalToConstant: 164),
            section.currentIndexLabel.topAnchor.constraint(equalTo: section.currentIndexCard.topAnchor, constant: 18),
            section.currentIndexLabel.leadingAnchor.constraint(equalTo: section.currentIndexCard.leadingAnchor, constant: 22),
            section.startIndexButton.topAnchor.constraint(equalTo: section.currentIndexLabel.bottomAnchor, constant: 18),
            section.startIndexButton.leadingAnchor.constraint(equalTo: section.currentIndexLabel.leadingAnchor),
            section.startIndexButton.widthAnchor.constraint(equalToConstant: 194),
            section.startIndexButton.heightAnchor.constraint(equalToConstant: 44),
            section.pauseIndexButton.centerYAnchor.constraint(equalTo: section.startIndexButton.centerYAnchor),
            section.pauseIndexButton.leadingAnchor.constraint(equalTo: section.startIndexButton.trailingAnchor, constant: 16),
            section.pauseIndexButton.widthAnchor.constraint(equalToConstant: 194),
            section.pauseIndexButton.heightAnchor.constraint(equalToConstant: 44),
            section.cancelIndexButton.centerYAnchor.constraint(equalTo: section.startIndexButton.centerYAnchor),
            section.cancelIndexButton.leadingAnchor.constraint(equalTo: section.pauseIndexButton.trailingAnchor, constant: 16),
            section.cancelIndexButton.widthAnchor.constraint(equalToConstant: 194),
            section.cancelIndexButton.heightAnchor.constraint(equalToConstant: 44),
            section.clearCurrentIndexButton.topAnchor.constraint(equalTo: section.startIndexButton.bottomAnchor, constant: 10),
            section.clearCurrentIndexButton.leadingAnchor.constraint(equalTo: section.currentIndexLabel.leadingAnchor),
            section.clearCurrentIndexButton.widthAnchor.constraint(equalToConstant: 194),
            section.clearCurrentIndexButton.heightAnchor.constraint(equalToConstant: 44),
            section.clearCurrentWordsButton.centerYAnchor.constraint(equalTo: section.clearCurrentIndexButton.centerYAnchor),
            section.clearCurrentWordsButton.leadingAnchor.constraint(equalTo: section.clearCurrentIndexButton.trailingAnchor, constant: 16),
            section.clearCurrentWordsButton.widthAnchor.constraint(equalToConstant: 194),
            section.clearCurrentWordsButton.heightAnchor.constraint(equalToConstant: 44),

            section.vectorCacheCard.topAnchor.constraint(equalTo: section.currentIndexCard.bottomAnchor, constant: 14),
            section.vectorCacheCard.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.vectorCacheCard.widthAnchor.constraint(equalToConstant: formWidth),
            section.vectorCacheCard.heightAnchor.constraint(equalToConstant: 138),
            section.cacheLabel.topAnchor.constraint(equalTo: section.vectorCacheCard.topAnchor, constant: 18),
            section.cacheLabel.leadingAnchor.constraint(equalTo: section.vectorCacheCard.leadingAnchor, constant: 22),
            section.cacheStatusLabel.centerYAnchor.constraint(equalTo: section.cacheLabel.centerYAnchor),
            section.cacheStatusLabel.leadingAnchor.constraint(equalTo: section.cacheLabel.trailingAnchor, constant: 18),
            section.cacheStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: section.vectorCacheCard.trailingAnchor, constant: -22),
            section.clearVectorCacheButton.topAnchor.constraint(equalTo: section.cacheLabel.bottomAnchor, constant: 20),
            section.clearVectorCacheButton.leadingAnchor.constraint(equalTo: section.vectorCacheCard.leadingAnchor, constant: 22),
            section.clearVectorCacheButton.widthAnchor.constraint(equalToConstant: 194),
            section.clearVectorCacheButton.heightAnchor.constraint(equalToConstant: 44),
            section.cacheDisclosureButton.trailingAnchor.constraint(equalTo: section.vectorCacheCard.trailingAnchor, constant: -22),
            section.cacheDisclosureButton.centerYAnchor.constraint(equalTo: section.vectorCacheCard.centerYAnchor),
            section.cacheDisclosureButton.widthAnchor.constraint(equalToConstant: 32),
            section.cacheDisclosureButton.heightAnchor.constraint(equalToConstant: 32),
            section.vectorCacheCard.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -8)
        ]
    }
}
