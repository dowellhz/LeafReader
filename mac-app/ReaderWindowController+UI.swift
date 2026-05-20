import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    func buildUI() {
        guard let contentView = window?.contentView else { return }
        installKeyboardPagingMonitor()

        configurePDFReaderView()
        configureReaderWebView()

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

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
        selectionActionToolbar.onCopy = { [weak self] in
            self?.runSelectionToolbarAction(.copy)
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
