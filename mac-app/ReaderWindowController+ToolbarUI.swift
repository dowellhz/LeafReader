import Cocoa

extension ReaderWindowController {
    func configureToolbarViews() -> ReaderToolbarSetup {
        let toolbar = readerBarView()
        let zoomOut = plainButton(title: "-", action: #selector(ReaderWindowController.zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(ReaderWindowController.zoomIn))
        let leftDivider = divider()
        let rightDivider = divider()
        let zoomGroup = NSView()

        toolbarView = toolbar
        configureTitleControls()
        configureZoomControls(zoomGroup: zoomGroup, zoomOut: zoomOut, zoomIn: zoomIn, leftDivider: leftDivider, rightDivider: rightDivider)
        configurePageAndSearchControls()
        configureTopRightControls()

        for view in [titleLabel, coverImageView, zoomGroup, pageLabel, searchUnderlineButton!, searchButton!, pageLayoutButton!, cropButton!, fullScreenButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        return ReaderToolbarSetup(
            toolbar: toolbar,
            zoomOut: zoomOut,
            zoomIn: zoomIn,
            leftDivider: leftDivider,
            rightDivider: rightDivider,
            zoomGroup: zoomGroup
        )
    }

    func configureBottomBarViews() -> ReaderBottomBarSetup {
        let bottomBar = readerBarView()
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))
        let navigationStack = NSStackView()

        bottomBarView = bottomBar
        recentButton = capsuleButton(title: AppText.localized("书架", "Shelf"), symbol: "books.vertical", action: #selector(showRecentDocuments))
        vocabularyButton = capsuleButton(title: AppText.localized("背单词", "Vocab"), symbol: "text.book.closed", action: #selector(showVocabularyBook))
        farthestPositionButton = capsuleButton(title: AppText.localized("上次位置", "Last"), symbol: "arrow.turn.down.right", action: #selector(goToFarthestReadingPosition))
        farthestPositionButton.toolTip = AppText.localized("跳到本书阅读过的最远位置", "Jump to the farthest read position in this book")
        tocButton = capsuleButton(title: AppText.localized("目录", "TOC"), symbol: "list.bullet", action: #selector(showTableOfContents))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)
        embeddingPauseButton = capsuleButton(title: AppText.localized("暂停", "Pause"), symbol: "pause.fill", action: #selector(toggleEmbeddingBackfillPaused))
        embeddingPauseButton.toolTip = AppText.localized("暂停/继续 AI 分析", "Pause/resume AI analysis")
        embeddingCancelButton = capsuleButton(title: AppText.localized("取消", "Cancel"), symbol: "xmark", action: #selector(cancelEmbeddingBackfill))
        embeddingCancelButton.toolTip = AppText.localized("取消本次 AI 分析任务", "Cancel this AI analysis task")

        embeddingStatusLabel.font = AppFont.semibold(ofSize: 12)
        embeddingStatusLabel.alignment = .right
        embeddingStatusLabel.lineBreakMode = .byTruncatingMiddle
        updateEmbeddingStatusTextColor()
        embeddingStatusLabel.isHidden = true
        embeddingPauseButton.isHidden = true
        embeddingCancelButton.isHidden = true

        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.distribution = .fill
        navigationStack.spacing = ReaderUILayout.navigationStackSpacing
        for button in [tocButton!, coverButton!, prevButton!, nextButton!, farthestPositionButton!] {
            button.translatesAutoresizingMaskIntoConstraints = false
            navigationStack.addArrangedSubview(button)
        }

        for view in [settingsButton, recentButton!, vocabularyButton!, navigationStack, embeddingStatusLabel, embeddingPauseButton!, embeddingCancelButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(view)
        }

        return ReaderBottomBarSetup(bottomBar: bottomBar, settingsButton: settingsButton, navigationStack: navigationStack)
    }

    func configureTitleControls() {
        titleLabel.font = AppFont.semibold(ofSize: 15)
        titleLabel.textColor = NSColor(red: 0.1, green: 0.11, blue: 0.14, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false

        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.backgroundColor = NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1).cgColor
        coverImageView.layer?.borderColor = NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1).cgColor
        coverImageView.layer?.borderWidth = 1
        coverImageView.layer?.cornerRadius = 3
        coverImageView.layer?.masksToBounds = true
        coverImageView.isHidden = true
    }

    func configureZoomControls(zoomGroup: NSView, zoomOut: NSButton, zoomIn: NSButton, leftDivider: NSView, rightDivider: NSView) {
        zoomGroupView = zoomGroup
        zoomGroup.wantsLayer = true
        zoomGroup.layer?.backgroundColor = NSColor.white.cgColor
        zoomGroup.layer?.borderColor = NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1).cgColor
        zoomGroup.layer?.borderWidth = 1
        zoomGroup.layer?.cornerRadius = 7

        zoomField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        zoomField.alignment = .center
        zoomField.isBordered = false
        zoomField.drawsBackground = false
        zoomField.focusRingType = .none
        zoomField.isEditable = true
        zoomField.isSelectable = true
        zoomField.delegate = self
        zoomField.target = self
        zoomField.action = #selector(applyZoomFromField)

        for view in [zoomOut, leftDivider, zoomField, rightDivider, zoomIn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            zoomGroup.addSubview(view)
        }
    }

    func configurePageAndSearchControls() {
        pageLabel.font = AppFont.semibold(ofSize: 15)
        pageLabel.alignment = .center
        pageLabel.isBordered = false
        pageLabel.drawsBackground = false
        pageLabel.focusRingType = .none
        pageLabel.isEditable = true
        pageLabel.isSelectable = true
        pageLabel.delegate = self
        pageLabel.target = self
        pageLabel.action = #selector(applyPageFromField)
        pageLabel.toolTip = AppText.localized("输入页码后按回车跳转", "Enter a page number and press Return")
        updatePageLabelTextColor()

        searchUnderlineButton = SearchUnderlineButton(title: "", target: self, action: #selector(showSearchOverlay))
        searchUnderlineButton.toolTip = AppText.localized("搜索文档", "Search document")
        searchUnderlineButton.isDark = ReaderTheme.selected == .dark
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索文档", "Search document")
    }

    func configureTopRightControls() {
        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        pageLayoutButton = capsuleButton(title: "", symbol: "rectangle.split.2x1", action: #selector(togglePDFPageLayout))
        pageLayoutButton.toolTip = AppText.localized("切换单页/双页浏览", "Toggle single/two-page view")
        cropButton = capsuleButton(title: "", symbol: "crop", action: #selector(togglePDFMarginCrop))
        cropButton.toolTip = AppText.localized("裁掉 PDF 页面外侧空白", "Crop outer PDF margins")
        updatePDFPageLayoutButton()
        updatePDFMarginCropButton()
    }

    func readerBarView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        view.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        view.layer?.borderWidth = 1
        return view
    }
}
