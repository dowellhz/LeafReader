import Cocoa
import PDFKit
import WebKit

private struct ReaderToolbarSetup {
    let toolbar: NSView
    let zoomOut: NSButton
    let zoomIn: NSButton
    let leftDivider: NSView
    let rightDivider: NSView
    let zoomGroup: NSView
}

private struct ReaderBottomBarSetup {
    let bottomBar: NSView
    let settingsButton: NSButton
}

private enum ReaderUILayout {
    static let toolbarHeight: CGFloat = 58
    static let bottomBarHeight: CGFloat = 52
    static let collapsedAIPanelWidth: CGFloat = 1
    static let resizeHandleWidth: CGFloat = 6
    static let aiHandleTopOffset: CGFloat = 90

    static let settingsLeading: CGFloat = 18
    static let settingsButtonSize: CGFloat = 24
    static let shelfButtonLeading: CGFloat = 18
    static let shelfButtonWidth: CGFloat = 88
    static let vocabularyButtonLeading: CGFloat = 10
    static let vocabularyButtonWidth: CGFloat = 92
    static let bottomButtonHeight: CGFloat = 30

    static let coverLeading: CGFloat = 128
    static let coverSize = CGSize(width: 28, height: 38)
    static let titleLeading: CGFloat = 10
    static let titleMaxWidth: CGFloat = 230

    static let zoomLeadingMinimum: CGFloat = 24
    static let zoomCenterOffset: CGFloat = -80
    static let zoomGroupSize = CGSize(width: 132, height: 32)
    static let zoomButtonWidth: CGFloat = 40
    static let zoomDividerWidth: CGFloat = 1
    static let zoomFieldWidth: CGFloat = 50

    static let pageLabelCenterOffset: CGFloat = 130
    static let pageLabelWidth: CGFloat = 140
    static let searchUnderlineLeading: CGFloat = 6
    static let searchUnderlineSize = CGSize(width: 74, height: 28)
    static let searchButtonLeading: CGFloat = 2
    static let iconButtonSize: CGFloat = 28

    static let pageLayoutTrailing: CGFloat = -8
    static let pageLayoutButtonWidth: CGFloat = 84
    static let fitWidthTrailing: CGFloat = -8
    static let fitWidthButtonWidth: CGFloat = 84
    static let fullScreenTrailing: CGFloat = -14
    static let fullScreenButtonWidth: CGFloat = 76
    static let toolbarButtonHeight: CGFloat = 30

    static let searchOverlayTop: CGFloat = 10
    static let searchOverlaySize = CGSize(width: 560, height: 70)
    static let loadingIndicatorYOffset: CGFloat = -16
    static let loadingLabelTop: CGFloat = 14
    static let loadingLabelHorizontalInset: CGFloat = 32

    static let tocTrailing: CGFloat = -10
    static let tocButtonWidth: CGFloat = 88
    static let coverButtonTrailing: CGFloat = -12
    static let coverButtonWidth: CGFloat = 100
    static let prevButtonCenterOffset: CGFloat = -48
    static let readerNavButtonWidth: CGFloat = 84
    static let nextButtonLeading: CGFloat = 12

    static let embeddingTrailing: CGFloat = -18
    static let embeddingButtonWidth: CGFloat = 58
    static let embeddingButtonHeight: CGFloat = 26
    static let embeddingButtonSpacing: CGFloat = -8
    static let embeddingStatusTrailing: CGFloat = -10
    static let embeddingStatusLeadingMinimum: CGFloat = 16
    static let embeddingStatusMaxWidth: CGFloat = 220
}

extension ReaderWindowController {
    func buildUI() {
        guard let contentView = window?.contentView else { return }
        installKeyboardPagingMonitor()

        configurePDFReaderView()
        configureReaderWebView()

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        pdfContainer.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }

        let toolbarSetup = configureToolbarViews()
        let toolbar = toolbarSetup.toolbar
        let bottomBarSetup = configureBottomBarViews()
        let bottomBar = bottomBarSetup.bottomBar
        pdfContainer.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(pdfContainer)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(pdfView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(webView)
        pdfDimOverlay.wantsLayer = true
        pdfDimOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        pdfDimOverlay.translatesAutoresizingMaskIntoConstraints = false
        pdfDimOverlay.isHidden = true
        pdfContainer.addSubview(pdfDimOverlay, positioned: .above, relativeTo: pdfView)
        for view in [aiPanel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentArea.addSubview(view)
        }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(resizeHandle, positioned: .above, relativeTo: aiPanel)
        aiPanelWidthConstraint = aiPanel.widthAnchor.constraint(equalToConstant: ReaderUILayout.collapsedAIPanelWidth)
        aiPanelWidthConstraint.priority = .required
        aiPanelWidthConstraint.isActive = true

        for view in [toolbar, contentArea, bottomBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        aiHandleButton.target = self
        aiHandleButton.action = #selector(toggleAIPanel)
        aiHandleButton.isBordered = false
        aiHandleButton.wantsLayer = true
        aiHandleButton.layer?.shadowColor = NSColor.black.cgColor
        aiHandleButton.layer?.shadowOpacity = 0.18
        aiHandleButton.layer?.shadowRadius = 12
        aiHandleButton.layer?.shadowOffset = CGSize(width: -2, height: -2)
        aiHandleButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(aiHandleButton, positioned: .above, relativeTo: contentArea)
        aiHandleLeadingConstraint = aiHandleButton.leadingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SideHandleButton.handleWidth)

        configureAIPanelCallbacks()
        configureSearchOverlay(in: contentView)
        configureLoadingOverlay()
        contentView.addSubview(loadingOverlay, positioned: .above, relativeTo: searchOverlay)

        installReaderLayoutConstraints(
            contentView: contentView,
            toolbarSetup: toolbarSetup,
            bottomBarSetup: bottomBarSetup
        )

        DispatchQueue.main.async { [weak self] in
            self?.setAIPanelCollapsed(true, animated: false)
        }
        applyReaderTheme()
        scheduleSessionRestoreAfterInitialPaint()
    }

    private func installReaderLayoutConstraints(
        contentView: NSView,
        toolbarSetup: ReaderToolbarSetup,
        bottomBarSetup: ReaderBottomBarSetup
    ) {
        let toolbar = toolbarSetup.toolbar
        let zoomOut = toolbarSetup.zoomOut
        let zoomIn = toolbarSetup.zoomIn
        let zoomGroup = toolbarSetup.zoomGroup
        let leftDivider = toolbarSetup.leftDivider
        let rightDivider = toolbarSetup.rightDivider
        let bottomBar = bottomBarSetup.bottomBar
        let settingsButton = bottomBarSetup.settingsButton

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarHeight),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomBarHeight),

            contentArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            pdfContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: aiPanel.leadingAnchor),

            pdfView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            pdfDimOverlay.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfDimOverlay.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfDimOverlay.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfDimOverlay.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            webView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            aiPanel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            resizeHandle.topAnchor.constraint(equalTo: contentArea.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: aiPanel.leadingAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: ReaderUILayout.resizeHandleWidth),

            aiHandleButton.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: ReaderUILayout.aiHandleTopOffset),
            aiHandleLeadingConstraint,
            aiHandleButton.widthAnchor.constraint(equalToConstant: SideHandleButton.handleWidth),
            aiHandleButton.heightAnchor.constraint(equalToConstant: SideHandleButton.handleHeight),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: ReaderUILayout.settingsLeading),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.settingsButtonSize),
            settingsButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.settingsButtonSize),

            recentButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: ReaderUILayout.shelfButtonLeading),
            recentButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            recentButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.shelfButtonWidth),
            recentButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            vocabularyButton.leadingAnchor.constraint(equalTo: recentButton.trailingAnchor, constant: ReaderUILayout.vocabularyButtonLeading),
            vocabularyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            vocabularyButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.vocabularyButtonWidth),
            vocabularyButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            coverImageView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: ReaderUILayout.coverLeading),
            coverImageView.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: ReaderUILayout.coverSize.width),
            coverImageView.heightAnchor.constraint(equalToConstant: ReaderUILayout.coverSize.height),

            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: ReaderUILayout.titleLeading),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: ReaderUILayout.titleMaxWidth),

            zoomGroup.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: ReaderUILayout.zoomLeadingMinimum),
            zoomGroup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomGroup.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.zoomCenterOffset),
            zoomGroup.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.width),
            zoomGroup.heightAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.height),

            zoomOut.leadingAnchor.constraint(equalTo: zoomGroup.leadingAnchor),
            zoomOut.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomOut.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomButtonWidth),
            leftDivider.leadingAnchor.constraint(equalTo: zoomOut.trailingAnchor),
            leftDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            leftDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomField.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: zoomGroup.centerYAnchor),
            zoomField.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomFieldWidth),
            rightDivider.leadingAnchor.constraint(equalTo: zoomField.trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomIn.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            zoomIn.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomIn.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: zoomGroup.trailingAnchor),

            pageLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.pageLabelCenterOffset),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: ReaderUILayout.pageLabelWidth),

            searchUnderlineButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: ReaderUILayout.searchUnderlineLeading),
            searchUnderlineButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchUnderlineButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.width),
            searchUnderlineButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.height),

            searchButton.leadingAnchor.constraint(equalTo: searchUnderlineButton.trailingAnchor, constant: ReaderUILayout.searchButtonLeading),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),
            searchButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),

            pageLayoutButton.trailingAnchor.constraint(equalTo: fitWidthButton.leadingAnchor, constant: ReaderUILayout.pageLayoutTrailing),
            pageLayoutButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLayoutButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.pageLayoutButtonWidth),
            pageLayoutButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            fitWidthButton.trailingAnchor.constraint(equalTo: fullScreenButton.leadingAnchor, constant: ReaderUILayout.fitWidthTrailing),
            fitWidthButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fitWidthButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.fitWidthButtonWidth),
            fitWidthButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: ReaderUILayout.fullScreenTrailing),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.fullScreenButtonWidth),
            fullScreenButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: ReaderUILayout.searchOverlayTop),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.width),
            searchOverlay.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.height),

            loadingOverlay.topAnchor.constraint(equalTo: contentArea.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: ReaderUILayout.loadingIndicatorYOffset),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: ReaderUILayout.loadingLabelTop),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlay.leadingAnchor, constant: ReaderUILayout.loadingLabelHorizontalInset),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlay.trailingAnchor, constant: -ReaderUILayout.loadingLabelHorizontalInset),

            tocButton.trailingAnchor.constraint(equalTo: coverButton.leadingAnchor, constant: ReaderUILayout.tocTrailing),
            tocButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            tocButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.tocButtonWidth),
            tocButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            coverButton.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: ReaderUILayout.coverButtonTrailing),
            coverButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            coverButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.coverButtonWidth),
            coverButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            prevButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: ReaderUILayout.prevButtonCenterOffset),
            prevButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readerNavButtonWidth),
            prevButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: ReaderUILayout.nextButtonLeading),
            nextButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readerNavButtonWidth),
            nextButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            embeddingCancelButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: ReaderUILayout.embeddingTrailing),
            embeddingCancelButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingCancelButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonWidth),
            embeddingCancelButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonHeight),
            embeddingPauseButton.trailingAnchor.constraint(equalTo: embeddingCancelButton.leadingAnchor, constant: ReaderUILayout.embeddingButtonSpacing),
            embeddingPauseButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingPauseButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonWidth),
            embeddingPauseButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonHeight),
            embeddingStatusLabel.trailingAnchor.constraint(equalTo: embeddingPauseButton.leadingAnchor, constant: ReaderUILayout.embeddingStatusTrailing),
            embeddingStatusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nextButton.trailingAnchor, constant: ReaderUILayout.embeddingStatusLeadingMinimum),
            embeddingStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: ReaderUILayout.embeddingStatusMaxWidth)
        ])
    }

    private func configureToolbarViews() -> ReaderToolbarSetup {
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

        for view in [titleLabel, coverImageView, zoomGroup, pageLabel, searchUnderlineButton!, searchButton!, pageLayoutButton!, fitWidthButton!, fullScreenButton!] {
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

    private func configureBottomBarViews() -> ReaderBottomBarSetup {
        let bottomBar = readerBarView()
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))

        bottomBarView = bottomBar
        recentButton = capsuleButton(title: AppText.localized("书架", "Shelf"), symbol: "books.vertical", action: #selector(showRecentDocuments))
        vocabularyButton = capsuleButton(title: AppText.localized("背单词", "Vocab"), symbol: "text.book.closed", action: #selector(showVocabularyBook))
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

        for view in [settingsButton, recentButton!, vocabularyButton!, tocButton!, coverButton!, prevButton!, nextButton!, embeddingStatusLabel, embeddingPauseButton!, embeddingCancelButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(view)
        }

        return ReaderBottomBarSetup(bottomBar: bottomBar, settingsButton: settingsButton)
    }

    private func configureTitleControls() {
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

    private func configureZoomControls(zoomGroup: NSView, zoomOut: NSButton, zoomIn: NSButton, leftDivider: NSView, rightDivider: NSView) {
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

    private func configurePageAndSearchControls() {
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

    private func configureTopRightControls() {
        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        pageLayoutButton = capsuleButton(title: "", symbol: "rectangle.split.2x1", action: #selector(togglePDFPageLayout))
        pageLayoutButton.toolTip = AppText.localized("切换单页/双页浏览", "Toggle single/two-page view")
        fitWidthButton = capsuleButton(title: AppText.localized("适宽", "Fit Width"), symbol: "arrow.left.and.right", action: #selector(fitPDFToWidth))
        fitWidthButton.toolTip = AppText.localized("让当前 PDF 适合阅读区宽度", "Fit the PDF to the reader width")
        updatePDFPageLayoutButton()
    }

    private func readerBarView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        view.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        view.layer?.borderWidth = 1
        return view
    }

    private func configureAIPanelCallbacks() {
        resizeHandle.onDragDeltaX = { [weak self] deltaX in
            self?.resizeAIPanel(deltaX: deltaX)
        }
        resizeHandle.onDragEnded = { [weak self] in
            self?.finishAIPanelResize()
        }
        aiPanel.onAskSelectedText = { [weak self] text in
            guard let self else { return nil }
            return self.contextForCurrentSelection(selectedText: text)
        }
        aiPanel.onSelectedWordQuestionStarted = { [weak self] text in
            guard let self else { return nil }
            if self.currentDocumentKind == .pdf {
                return self.persistSelectedWordIfNeeded(self.pdfView.currentSelection, text: text)
            }
            return self.persistSelectedWebWordIfNeeded(text: text)
        }
        aiPanel.onLinkedAnswerCompleted = { [weak self] linkID, question, answer in
            self?.updateStoredLinkedWordAnswer(linkID: linkID, question: question, answer: answer)
        }
        aiPanel.onLinkedAnswerFailed = { [weak self] linkID in
            self?.discardPendingLinkedWord(linkID: linkID)
        }
        aiPanel.onLinkedWordAnswerAvailable = { [weak self] linkID in
            self?.linkedWordAnswer(for: linkID)
        }
        aiPanel.onLinkedBubbleSelected = { [weak self] linkID in
            self?.jumpToStoredLinkedWord(linkID: linkID)
        }
        aiPanel.onSummarizeCurrentContent = { [weak self] completion in
            self?.currentSummaryContent(completion: completion)
        }
        aiPanel.onTranslateCurrentContent = { [weak self] completion in
            self?.currentTranslationContent(completion: completion)
        }
        aiPanel.onCurrentReadingContent = { [weak self] completion in
            self?.currentReadingQuestionContent(completion: completion)
        }
        aiPanel.onDocumentQuestionPrompt = { [weak self] question, context, completion in
            self?.documentAgentPrompt(question: question, context: context, completion: completion)
        }
        aiPanel.onDocumentQuestionCancelled = { [weak self] in
            self?.cancelDocumentAgentPrompt()
        }
        aiPanel.onSettingsRequired = { [weak self] in
            self?.openAISettings()
        }
        aiPanel.onConversationChanged = { [weak self] conversation in
            self?.saveAIConversationIfNeeded(conversation)
        }
        aiPanel.onConversationSourcesChanged = { [weak self] sources in
            self?.reconcileAISourceUnderlines(activeSources: sources)
        }
        aiPanel.onCurrentSourceLocation = { [weak self] in
            self?.currentAIConversationSourceLocation()
        }
        aiPanel.onConversationBubbleSelected = { [weak self] sourceLocation in
            self?.jumpToAIConversationSource(sourceLocation)
        }
        aiPanel.onNonFollowUpSelectionInteraction = { [weak self] in
            self?.clearReaderSelectionForBubbleSelection()
        }
        selectionActionToolbar.onTranslate = { [weak self] in
            self?.runSelectionToolbarAction(.translate)
        }
        selectionActionToolbar.onExplain = { [weak self] in
            self?.runSelectionToolbarAction(.explain)
        }
        selectionActionToolbar.onAddWord = { [weak self] in
            self?.runSelectionToolbarAction(.addWord)
        }
        selectionActionToolbar.onSummarize = { [weak self] in
            self?.runSelectionToolbarAction(.summarize)
        }
        selectionActionToolbar.onSpeak = { [weak self] in
            self?.runSelectionToolbarAction(.speak)
        }
    }

    private func configureSearchOverlay(in contentView: NSView) {
        searchOverlay.isHidden = true
        searchOverlay.onSubmit = { [weak self] query in
            self?.performSearch(query)
        }
        searchOverlay.onPrevious = { [weak self] in
            self?.goToPreviousSearchResult()
        }
        searchOverlay.onNext = { [weak self] in
            self?.goToNextSearchResult()
        }
        searchOverlay.onClose = { [weak self] in
            self?.hideSearchOverlay()
        }
        searchOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchOverlay, positioned: .above, relativeTo: contentArea)
    }

    func configurePDFReaderView() {
        pdfView = EdgePagingPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayBox = .cropBox
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        pdfView.delegate = self
        pdfView.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
        pdfView.onScrollPastPageEdge = { [weak self] direction in
            self?.turnPageFromScroll(direction)
        }
    }

    func configureReaderWebView() {
        let webConfiguration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "selectionChanged")
        userContentController.add(self, name: "scrollChanged")
        userContentController.add(self, name: "webWordClicked")
        userContentController.add(self, name: "webAISourceClicked")
        userContentController.addUserScript(WKUserScript(
            source: Self.webDocumentUserScriptSource(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        webConfiguration.userContentController = userContentController
        webView = ReaderWebView(frame: .zero, configuration: webConfiguration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        webView.isHidden = true
        webView.navigationDelegate = self
        webView.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
    }

}
