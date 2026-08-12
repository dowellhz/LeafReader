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
        _ = NetworkConnectivityMonitor.shared
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkConnectivityChanged(_:)),
            name: .leafReaderNetworkConnectivityChanged,
            object: nil
        )

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = ReaderTheme.selected.chromeBackgroundColor.cgColor
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
        pdfView.backgroundColor = ReaderTheme.selected.chromeBackgroundColor
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
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "selectionChanged")
        userContentController.add(self, name: "scrollChanged")
        userContentController.add(self, name: "webWordClicked")
        userContentController.add(self, name: "webNoteClicked")
        userContentController.add(self, name: "webAISourceClicked")
        userContentController.addUserScript(WKUserScript(
            source: WebDocumentSecurityPolicy.DOMSanitizerScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        userContentController.addUserScript(WKUserScript(
            source: Self.webDocumentUserScriptSource(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        webConfiguration.userContentController = userContentController
        webView = ReaderWebView(frame: .zero, configuration: webConfiguration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = ReaderTheme.selected.chromeBackgroundColor.cgColor
        webView.isHidden = true
        webView.navigationDelegate = self
        webView.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
    }

}
