import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    func buildUI() {
        guard let contentView = window?.contentView else { return }
        installKeyboardPagingMonitor()

        pdfView = EdgePagingPDFView()
        pdfView.wantsLayer = true
        pdfView.layer?.masksToBounds = true
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

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        pdfContainer.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }

        let toolbar = NSView()
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        toolbar.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        toolbar.layer?.borderWidth = 1

        let bottomBar = NSView()
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        bottomBar.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        bottomBar.layer?.borderWidth = 1

        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))
        titleLabel.font = AppFont.semibold(ofSize: 15)
        titleLabel.textColor = NSColor(red: 0.1, green: 0.11, blue: 0.14, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false
        titleLabel.toolTip = AppText.localized("从当前目录选择文件", "Choose a file from the current folder")
        titleLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openPDFInCurrentDirectory)))

        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.backgroundColor = NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1).cgColor
        coverImageView.layer?.borderColor = NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1).cgColor
        coverImageView.layer?.borderWidth = 1
        coverImageView.layer?.cornerRadius = 3
        coverImageView.layer?.masksToBounds = true
        coverImageView.isHidden = true
        coverImageView.toolTip = AppText.localized("从当前目录选择文件", "Choose a file from the current folder")
        coverImageView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openPDFInCurrentDirectory)))

        let zoomOut = plainButton(title: "-", action: #selector(ReaderWindowController.zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(ReaderWindowController.zoomIn))
        let zoomGroup = NSView()
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

        let leftDivider = divider()
        let rightDivider = divider()
        for view in [zoomOut, leftDivider, zoomField, rightDivider, zoomIn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            zoomGroup.addSubview(view)
        }
        toolbarView = toolbar
        bottomBarView = bottomBar
        zoomGroupView = zoomGroup

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

        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        tocButton = capsuleButton(title: AppText.localized("目录", "TOC"), symbol: "list.bullet", action: #selector(showTableOfContents))
        recentButton = capsuleButton(title: AppText.localized("书架", "Shelf"), symbol: "books.vertical", action: #selector(showRecentDocuments))
        vocabularyButton = capsuleButton(title: AppText.localized("背单词", "Vocab"), symbol: "text.book.closed", action: #selector(showVocabularyBook))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)
        pageLayoutButton = capsuleButton(title: "", symbol: "rectangle.split.2x1", action: #selector(togglePDFPageLayout))
        pageLayoutButton.toolTip = AppText.localized("切换单页/双页浏览", "Toggle single/two-page view")
        updatePDFPageLayoutButton()
        embeddingPauseButton = capsuleButton(title: AppText.localized("暂停", "Pause"), symbol: "pause.fill", action: #selector(toggleEmbeddingBackfillPaused))
        embeddingPauseButton.toolTip = AppText.localized("暂停/继续 AI 分析", "Pause/resume AI analysis")
        embeddingCancelButton = capsuleButton(title: AppText.localized("取消", "Cancel"), symbol: "xmark", action: #selector(cancelEmbeddingBackfill))
        embeddingCancelButton.toolTip = AppText.localized("取消本次 AI 分析任务", "Cancel this AI analysis task")

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
        aiPanelWidthConstraint = aiPanel.widthAnchor.constraint(equalToConstant: 1)
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
        configureLoadingOverlay()
        contentView.addSubview(loadingOverlay, positioned: .above, relativeTo: searchOverlay)

        for view in [titleLabel, coverImageView, zoomGroup, pageLabel, searchUnderlineButton!, searchButton!, pageLayoutButton!, fullScreenButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        embeddingStatusLabel.font = AppFont.semibold(ofSize: 12)
        embeddingStatusLabel.alignment = .right
        embeddingStatusLabel.lineBreakMode = .byTruncatingMiddle
        embeddingStatusLabel.isHidden = true
        embeddingPauseButton.isHidden = true
        embeddingCancelButton.isHidden = true

        for view in [settingsButton, recentButton!, vocabularyButton!, tocButton!, coverButton!, prevButton!, nextButton!, embeddingStatusLabel, embeddingPauseButton!, embeddingCancelButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(view)
        }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 58),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 52),

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
            resizeHandle.widthAnchor.constraint(equalToConstant: 6),

            aiHandleButton.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 90),
            aiHandleLeadingConstraint,
            aiHandleButton.widthAnchor.constraint(equalToConstant: SideHandleButton.handleWidth),
            aiHandleButton.heightAnchor.constraint(equalToConstant: SideHandleButton.handleHeight),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 18),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            recentButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 18),
            recentButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            recentButton.widthAnchor.constraint(equalToConstant: 88),
            recentButton.heightAnchor.constraint(equalToConstant: 30),

            vocabularyButton.leadingAnchor.constraint(equalTo: recentButton.trailingAnchor, constant: 10),
            vocabularyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            vocabularyButton.widthAnchor.constraint(equalToConstant: 92),
            vocabularyButton.heightAnchor.constraint(equalToConstant: 30),

            coverImageView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 128),
            coverImageView.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 28),
            coverImageView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 230),

            zoomGroup.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 24),
            zoomGroup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomGroup.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: -80),
            zoomGroup.widthAnchor.constraint(equalToConstant: 132),
            zoomGroup.heightAnchor.constraint(equalToConstant: 32),

            zoomOut.leadingAnchor.constraint(equalTo: zoomGroup.leadingAnchor),
            zoomOut.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomOut.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: 40),
            leftDivider.leadingAnchor.constraint(equalTo: zoomOut.trailingAnchor),
            leftDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            leftDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: 1),
            zoomField.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: zoomGroup.centerYAnchor),
            zoomField.widthAnchor.constraint(equalToConstant: 50),
            rightDivider.leadingAnchor.constraint(equalTo: zoomField.trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: 1),
            zoomIn.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            zoomIn.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomIn.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: zoomGroup.trailingAnchor),

            pageLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: 130),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: 140),

            searchUnderlineButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 6),
            searchUnderlineButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchUnderlineButton.widthAnchor.constraint(equalToConstant: 74),
            searchUnderlineButton.heightAnchor.constraint(equalToConstant: 28),

            searchButton.leadingAnchor.constraint(equalTo: searchUnderlineButton.trailingAnchor, constant: 2),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),

            pageLayoutButton.trailingAnchor.constraint(equalTo: fullScreenButton.leadingAnchor, constant: -12),
            pageLayoutButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLayoutButton.widthAnchor.constraint(equalToConstant: 84),
            pageLayoutButton.heightAnchor.constraint(equalToConstant: 30),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 76),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 30),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: 560),
            searchOverlay.heightAnchor.constraint(equalToConstant: 70),

            loadingOverlay.topAnchor.constraint(equalTo: contentArea.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: -16),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 14),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlay.leadingAnchor, constant: 32),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlay.trailingAnchor, constant: -32),

            tocButton.trailingAnchor.constraint(equalTo: coverButton.leadingAnchor, constant: -10),
            tocButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            tocButton.widthAnchor.constraint(equalToConstant: 88),
            tocButton.heightAnchor.constraint(equalToConstant: 30),

            coverButton.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -12),
            coverButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            coverButton.widthAnchor.constraint(equalToConstant: 100),
            coverButton.heightAnchor.constraint(equalToConstant: 30),

            prevButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: -48),
            prevButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 84),
            prevButton.heightAnchor.constraint(equalToConstant: 30),
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 12),
            nextButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 84),
            nextButton.heightAnchor.constraint(equalToConstant: 30),

            embeddingCancelButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -18),
            embeddingCancelButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingCancelButton.widthAnchor.constraint(equalToConstant: 58),
            embeddingCancelButton.heightAnchor.constraint(equalToConstant: 26),
            embeddingPauseButton.trailingAnchor.constraint(equalTo: embeddingCancelButton.leadingAnchor, constant: -8),
            embeddingPauseButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingPauseButton.widthAnchor.constraint(equalToConstant: 58),
            embeddingPauseButton.heightAnchor.constraint(equalToConstant: 26),
            embeddingStatusLabel.trailingAnchor.constraint(equalTo: embeddingPauseButton.leadingAnchor, constant: -10),
            embeddingStatusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nextButton.trailingAnchor, constant: 16),
            embeddingStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.setAIPanelCollapsed(true, animated: false)
        }
        applyReaderTheme()
        scheduleSessionRestoreAfterInitialPaint()
    }

}
