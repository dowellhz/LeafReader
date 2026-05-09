import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private static let preferredAIWidthDefaultsKey = "preferredAIWidth"

    private var pdfView: EdgePagingPDFView!
    private var webView: WKWebView!
    private let contentArea = NSView()
    private let pdfContainer = ClippingView()
    private let aiPanel = AIChatPanel()
    private let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    private let resizeHandle = ResizeHandleView()
    private let titleLabel = NSTextField(labelWithString: "Leaf Reader")
    private let coverImageView = NSImageView()
    private let pageLabel = NSTextField(labelWithString: AppText.noPDF)
    private let zoomField = NSTextField(string: "100%")
    private let searchOverlay = SearchOverlayView()
    private var fullScreenButton: NSButton!
    private var coverButton: NSButton!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var searchButton: NSButton!
    private var currentFileURL: URL?
    private var currentFileMD5: String?
    private var currentDocumentKind: ReaderDocumentKind = .pdf
    private var currentWebPlainText = ""
    private var currentWebSelectedText = ""
    private var webZoomPercent = 100
    private var webScrollProgress: Double = 0
    private var lastWebProgressSave = Date.distantPast
    private var lastPageIndex: Int?
    private var searchResults: [PDFSelection] = []
    private var searchResultIndex = 0
    private var lastSearchQuery = ""
    private var highlightedSelectionKeys = Set<String>()
    private var didRegisterSelectionObserver = false
    private var isRestoringSession = false
    private var isEditingZoomField = false
    private var isAIPanelCollapsed = true
    private var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    private var pendingAICollapseWorkItem: DispatchWorkItem?
    private var aiSettingsPanel: NSWindow?
    private weak var aiSettingsModelPopup: NSPopUpButton?
    private weak var aiSettingsLanguagePopup: NSPopUpButton?
    private weak var aiSettingsSecureKeyField: NSSecureTextField?
    private weak var aiSettingsPlainKeyField: NSTextField?
    private var aiHandleLeadingConstraint: NSLayoutConstraint!
    private var aiPanelWidthConstraint: NSLayoutConstraint!
    private var keyDownMonitor: Any?

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Leaf Reader"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        window.setFrameAutosaveName("LeafReaderClean")
        window.center()

        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollChanged")
        NotificationCenter.default.removeObserver(self)
    }

    private func buildUI() {
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
        pdfView.onScrollPastPageEdge = { [weak self] direction in
            self?.turnPageFromScroll(direction)
        }

        let webConfiguration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "selectionChanged")
        userContentController.add(self, name: "scrollChanged")
        userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              var lastScrollSent = 0;
              const sendSelection = () => {
                window.webkit.messageHandlers.selectionChanged.postMessage(String(window.getSelection() || ""));
              };
              const sendScroll = (force = false) => {
                const now = Date.now();
                if (!force && now - lastScrollSent < 200) return;
                lastScrollSent = now;
                const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                const progress = Math.max(0, Math.min(1, window.scrollY / height));
                window.webkit.messageHandlers.scrollChanged.postMessage(progress);
              };
              document.addEventListener("selectionchange", () => setTimeout(sendSelection, 0));
              document.addEventListener("mouseup", sendSelection);
              document.addEventListener("keyup", sendSelection);
              window.addEventListener("scroll", () => sendScroll(false), { passive: true });
              window.addEventListener("load", () => sendScroll(true));
              setTimeout(() => sendScroll(true), 250);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        webConfiguration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        webView.isHidden = true
        webView.navigationDelegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor

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

        let openButton = iconButton(symbol: "folder", action: #selector(openPDF))
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))
        titleLabel.font = NSFont.systemFont(ofSize: 15)
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

        let zoomOut = plainButton(title: "-", action: #selector(zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(zoomIn))
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
        zoomField.delegate = self
        zoomField.target = self
        zoomField.action = #selector(applyZoomFromField)

        let leftDivider = divider()
        let rightDivider = divider()
        for view in [zoomOut, leftDivider, zoomField, rightDivider, zoomIn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            zoomGroup.addSubview(view)
        }

        pageLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        pageLabel.alignment = .center
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索文档", "Search document")

        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)

        pdfContainer.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(pdfContainer)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(pdfView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(webView)

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
        aiPanel.onAskSelectedText = { [weak self] text in
            guard let self else { return nil }
            let context = self.contextForCurrentSelection(selectedText: text)
            if self.currentDocumentKind == .pdf {
                self.markSelectionIfWord(self.pdfView.currentSelection, text: text)
            }
            return context
        }
        aiPanel.onSettingsRequired = { [weak self] in
            self?.openAISettings()
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

        for view in [openButton, titleLabel, coverImageView, zoomGroup, pageLabel, searchButton!, fullScreenButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        for view in [settingsButton, coverButton!, prevButton!, nextButton!] {
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

            openButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 112),
            openButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 24),
            openButton.heightAnchor.constraint(equalToConstant: 24),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 18),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            coverImageView.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 28),
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

            searchButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 6),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 30),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: 560),
            searchOverlay.heightAnchor.constraint(equalToConstant: 70),

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
            nextButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.setAIPanelCollapsed(true, animated: false)
        }
        restoreSession()
    }

    private func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        return button
    }

    private func plainButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        return button
    }

    private func capsuleButton(title: String, symbol: String, action: Selector, imageOnRight: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = imageOnRight ? .imageRight : .imageLeft
        return button
    }

    private func divider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor
        return view
    }

    private func refreshLanguageUI() {
        aiPanel.refreshLanguage()
        fullScreenButton.title = window?.styleMask.contains(.fullScreen) == true ? AppText.windowed : AppText.fullScreen
        coverButton.title = AppText.cover
        prevButton.title = AppText.prev
        nextButton.title = AppText.next
        if pdfView.document == nil {
            pageLabel.stringValue = AppText.noPDF
        }
        fullScreenButton.image = NSImage(
            systemSymbolName: window?.styleMask.contains(.fullScreen) == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
        coverButton.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: AppText.cover)
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: AppText.prev)
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: AppText.next)
    }

    @objc private func openAISettings() {
        let selectedModel = AISettingsStore.selectedModel
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.18
        content.layer?.shadowRadius = 24
        content.layer?.shadowOffset = CGSize(width: 0, height: -8)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let titleLabel = NSTextField(labelWithString: AppText.settings)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "", target: self, action: #selector(cancelAISettings(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let modelHelpLabel = NSTextField(labelWithString: AppText.modelHelp)
        modelHelpLabel.font = NSFont.systemFont(ofSize: 16)
        modelHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        modelHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyHelpLabel = NSTextField(labelWithString: AppText.keyHelp)
        keyHelpLabel.font = NSFont.systemFont(ofSize: 16)
        keyHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        keyHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let languageHelpLabel = NSTextField(labelWithString: AppText.languageHelp)
        languageHelpLabel.font = NSFont.systemFont(ofSize: 16)
        languageHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        languageHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let modelLabel = NSTextField(labelWithString: AppText.model)
        modelLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.controlSize = .large
        modelPopup.font = NSFont.systemFont(ofSize: 18)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        for model in AISettingsStore.models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.id
        }
        if let index = AISettingsStore.models.firstIndex(where: { $0.id == selectedModel.id }) {
            modelPopup.selectItem(at: index)
        }

        let languageLabel = NSTextField(labelWithString: AppText.language)
        languageLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.controlSize = .large
        languagePopup.font = NSFont.systemFont(ofSize: 18)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        for language in AppText.Language.allCases {
            languagePopup.addItem(withTitle: language.title)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        if let index = AppText.Language.allCases.firstIndex(of: AppText.selectedLanguage) {
            languagePopup.selectItem(at: index)
        }

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        keyField.placeholderString = AppText.apiKeyPlaceholder
        keyField.controlSize = .regular
        keyField.font = NSFont.systemFont(ofSize: 22)
        keyField.isBordered = true
        keyField.drawsBackground = true
        keyField.isEditable = true
        keyField.isSelectable = true
        keyField.isEnabled = true
        keyField.translatesAutoresizingMaskIntoConstraints = false

        let plainKeyField = APIKeyTextField(string: AISettingsStore.apiKey(for: selectedModel))
        plainKeyField.placeholderString = AppText.apiKeyPlaceholder
        plainKeyField.controlSize = .regular
        plainKeyField.font = NSFont.systemFont(ofSize: 22)
        plainKeyField.isBordered = true
        plainKeyField.drawsBackground = true
        plainKeyField.isEditable = true
        plainKeyField.isSelectable = true
        plainKeyField.isEnabled = true
        plainKeyField.isHidden = true
        plainKeyField.translatesAutoresizingMaskIntoConstraints = false

        let eyeButton = NSButton(title: "", target: self, action: #selector(toggleAISettingsAPIKeyVisibility(_:)))
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
        eyeButton.isBordered = false
        eyeButton.contentTintColor = NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)
        eyeButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: AppText.cancel, target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let saveButton = NSButton(title: AppText.confirm, target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        modelPopup.target = self
        modelPopup.action = #selector(aiSettingsModelChanged(_:))
        modelPopup.identifier = NSUserInterfaceItemIdentifier("modelPopup")
        languagePopup.identifier = NSUserInterfaceItemIdentifier("languagePopup")
        keyField.identifier = NSUserInterfaceItemIdentifier("keyField")
        plainKeyField.identifier = NSUserInterfaceItemIdentifier("plainKeyField")
        for view in [titleLabel, closeButton, modelLabel, modelPopup, modelHelpLabel, languageLabel, languagePopup, languageHelpLabel, keyLabel, keyField, plainKeyField, eyeButton, keyHelpLabel, cancelButton, saveButton] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 48),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -48),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            modelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 66),
            modelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 14),
            modelPopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            modelPopup.heightAnchor.constraint(equalToConstant: 54),
            modelHelpLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 12),
            modelHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            keyLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 30),
            keyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 10),
            keyField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: eyeButton.leadingAnchor, constant: -10),
            keyField.heightAnchor.constraint(equalToConstant: 46),
            plainKeyField.topAnchor.constraint(equalTo: keyField.topAnchor),
            plainKeyField.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            plainKeyField.trailingAnchor.constraint(equalTo: keyField.trailingAnchor),
            plainKeyField.heightAnchor.constraint(equalTo: keyField.heightAnchor),
            eyeButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            eyeButton.centerYAnchor.constraint(equalTo: keyField.centerYAnchor),
            eyeButton.widthAnchor.constraint(equalToConstant: 28),
            eyeButton.heightAnchor.constraint(equalToConstant: 28),
            keyHelpLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 10),
            keyHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            languageLabel.topAnchor.constraint(equalTo: keyHelpLabel.bottomAnchor, constant: 30),
            languageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 14),
            languagePopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            languagePopup.heightAnchor.constraint(equalToConstant: 54),
            languageHelpLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 12),
            languageHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languageHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            saveButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -36),
            saveButton.widthAnchor.constraint(equalToConstant: 118),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 118),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        cancelButton.target = self
        cancelButton.action = #selector(cancelAISettings(_:))
        closeButton.target = self
        closeButton.action = #selector(cancelAISettings(_:))
        saveButton.target = self
        saveButton.action = #selector(saveAISettings(_:))
        saveButton.identifier = NSUserInterfaceItemIdentifier("saveAISettings")

        aiSettingsPanel = panel
        aiSettingsModelPopup = modelPopup
        aiSettingsLanguagePopup = languagePopup
        aiSettingsSecureKeyField = keyField
        aiSettingsPlainKeyField = plainKeyField

        window?.beginSheet(panel) { _ in }
        DispatchQueue.main.async {
            panel.makeKey()
            panel.makeFirstResponder(keyField)
        }
    }

    @objc private func saveAISettings(_ sender: NSButton) {
        guard
            let panel = aiSettingsPanel,
            let modelPopup = aiSettingsModelPopup,
            let keyField = currentAISettingsKeyField()
        else { return }

        let modelID = modelPopup.selectedItem?.representedObject as? String ?? AISettingsStore.selectedModel.id
        if let rawLanguage = aiSettingsLanguagePopup?.selectedItem?.representedObject as? String,
           let language = AppText.Language(rawValue: rawLanguage) {
            AppText.selectedLanguage = language
        }
        AISettingsStore.save(modelID: modelID, apiKey: keyField.stringValue)
        refreshLanguageUI()
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func cancelAISettings(_ sender: NSButton) {
        guard let panel = aiSettingsPanel else { return }
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func aiSettingsModelChanged(_ sender: NSPopUpButton) {
        guard
            let modelID = sender.selectedItem?.representedObject as? String,
            let model = AISettingsStore.models.first(where: { $0.id == modelID })
        else { return }

        let key = AISettingsStore.apiKey(for: model)
        aiSettingsSecureKeyField?.stringValue = key
        aiSettingsPlainKeyField?.stringValue = key
    }

    @objc private func toggleAISettingsAPIKeyVisibility(_ sender: NSButton) {
        guard let secureField = aiSettingsSecureKeyField, let plainField = aiSettingsPlainKeyField else { return }
        if plainField.isHidden {
            plainField.stringValue = secureField.stringValue
            plainField.isHidden = false
            secureField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: AppText.hideAPIKey)
            window?.makeFirstResponder(plainField)
        } else {
            secureField.stringValue = plainField.stringValue
            secureField.isHidden = false
            plainField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
            window?.makeFirstResponder(secureField)
        }
    }

    private func currentAISettingsKeyField() -> NSTextField? {
        if let plainField = aiSettingsPlainKeyField, !plainField.isHidden {
            return plainField
        }
        return aiSettingsSecureKeyField
    }

    private func findKeyField(in view: NSView) -> NSTextField? {
        if let keyField = view as? NSTextField,
           keyField.identifier?.rawValue == "keyField" || keyField.identifier?.rawValue == "plainKeyField" {
            return keyField
        }
        for subview in view.subviews {
            if let keyField = findKeyField(in: subview) {
                return keyField
            }
        }
        return nil
    }

    @objc private func toggleAIPanel() {
        cancelScheduledAICollapse()
        setAIPanelCollapsed(!isAIPanelCollapsed, animated: true)
    }

    private func scheduleAICollapse() {
        cancelScheduledAICollapse()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setAIPanelCollapsed(true, animated: true)
        }
        pendingAICollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
    }

    private func cancelScheduledAICollapse() {
        pendingAICollapseWorkItem?.cancel()
        pendingAICollapseWorkItem = nil
    }

    private func setAIPanelCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed, aiPanel.frame.width > 80 {
            preferredAIWidth = clampedAIWidth(aiPanel.frame.width)
            savePreferredAIWidth()
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            savePreferredAIWidth()
        }
        isAIPanelCollapsed = collapsed
        aiPanel.isHidden = false
        if collapsed {
            aiPanel.setContentVisible(false)
        }
        aiHandleButton.collapsedStyle = collapsed
        resizeHandle.isHidden = collapsed

        let targetAIWidth: CGFloat = collapsed ? 1 : clampedAIWidth(preferredAIWidth)
        let update = {
            self.aiPanelWidthConstraint.constant = targetAIWidth
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.refreshPDFLayoutAfterPanelChange()
            self.updateAIHandlePosition()
            if !collapsed {
                self.aiPanel.setContentVisible(true)
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.07
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                update()
            }
        } else {
            update()
        }
    }

    private func clampedAIWidth(_ width: CGFloat) -> CGFloat {
        let maxWidth = max(300, contentArea.bounds.width - 320)
        return min(max(width, 300), min(520, maxWidth))
    }

    private static func loadPreferredAIWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: preferredAIWidthDefaultsKey)
        guard width > 0 else { return 420 }
        return CGFloat(width)
    }

    private func savePreferredAIWidth() {
        UserDefaults.standard.set(Double(preferredAIWidth), forKey: Self.preferredAIWidthDefaultsKey)
    }

    private func updateAIHandlePosition() {
        let aiWidth = isAIPanelCollapsed ? 1 : aiPanelWidthConstraint.constant
        aiHandleLeadingConstraint.constant = isAIPanelCollapsed
            ? -SideHandleButton.handleWidth
            : -(aiWidth + SideHandleButton.handleWidth)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func refreshPDFLayoutAfterPanelChange() {
        pdfContainer.layoutSubtreeIfNeeded()
        pdfView.layoutSubtreeIfNeeded()
        pdfView.setNeedsDisplay(pdfView.bounds)
        pdfView.documentView?.setNeedsDisplay(pdfView.documentView?.bounds ?? .zero)
    }

    private func syncAIPanelLayoutAfterResize() {
        guard contentArea.bounds.width > 0 else { return }
        if isAIPanelCollapsed {
            aiPanelWidthConstraint.constant = 1
            aiPanel.setContentVisible(false)
            resizeHandle.isHidden = true
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            aiPanelWidthConstraint.constant = preferredAIWidth
            savePreferredAIWidth()
            aiPanel.setContentVisible(true)
            resizeHandle.isHidden = false
        }
        contentArea.layoutSubtreeIfNeeded()
        refreshPDFLayoutAfterPanelChange()
        updateAIHandlePosition()
    }

    private func resizeAIPanel(deltaX: CGFloat) {
        guard !isAIPanelCollapsed else { return }
        preferredAIWidth = clampedAIWidth(preferredAIWidth - deltaX)
        savePreferredAIWidth()
        aiPanelWidthConstraint.constant = preferredAIWidth
        contentArea.layoutSubtreeIfNeeded()
        refreshPDFLayoutAfterPanelChange()
        updateAIHandlePosition()
    }

    private func updateFullScreenButton() {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        fullScreenButton.title = isFullScreen ? AppText.windowed : AppText.fullScreen
        fullScreenButton.image = NSImage(
            systemSymbolName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
    }

    func windowDidResize(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    @objc private func openPDF() {
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadDocument(url)
        }
    }

    private func configureOpenPanel(_ panel: NSOpenPanel) {
        panel.allowedFileTypes = ["pdf", "epub", "docx"]
        panel.allowsOtherFileTypes = false
    }

    private func loadDocument(_ url: URL) {
        guard let kind = ReaderDocumentKind.kind(for: url) else { return }
        switch kind {
        case .pdf:
            loadPDF(url)
        case .epub, .docx:
            loadWebDocument(url, kind: kind)
        }
    }

    private func loadPDF(_ url: URL) {
        guard let document = PDFDocument(url: url) else { return }
        currentDocumentKind = .pdf
        pdfView.isHidden = false
        webView.isHidden = true
        pdfView.document = document
        currentFileURL = url
        currentFileMD5 = fileMD5(for: url)
        currentWebPlainText = ""
        currentWebSelectedText = ""
        highlightedSelectionKeys.removeAll()
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        updateCoverThumbnail(from: document)

        if !didRegisterSelectionObserver {
            didRegisterSelectionObserver = true
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        }

        restoreBookProgressOrGoHome()
        lastPageIndex = currentPageIndex()
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    private func loadWebDocument(_ url: URL, kind: ReaderDocumentKind) {
        do {
            let document = try WebDocumentLoader.load(url: url)
            currentDocumentKind = kind
            pdfView.isHidden = true
            webView.isHidden = false
            pdfView.document = nil
            currentFileURL = url
            currentFileMD5 = fileMD5(for: url)
            currentWebPlainText = document.plainText
            currentWebSelectedText = ""
            webZoomPercent = 100
            webScrollProgress = 0
            highlightedSelectionKeys.removeAll()
            searchResults.removeAll()
            searchResultIndex = 0
            lastSearchQuery = ""
            searchOverlay.setResultText("")
            aiPanel.setSelectedText("")
            titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
            if let coverImageURL = document.coverImageURL, let image = NSImage(contentsOf: coverImageURL) {
                coverImageView.image = image
            } else {
                coverImageView.image = NSImage(systemSymbolName: kind == .epub ? "book.closed" : "doc.text", accessibilityDescription: nil)
            }
            coverImageView.isHidden = false
            pageLabel.stringValue = "0%"
            zoomField.stringValue = "100%"
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
            webView.pageZoom = CGFloat(webZoomPercent) / 100
            restoreWebProgressAfterLoad()
            saveSession()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateCoverThumbnail(from document: PDFDocument) {
        guard let firstPage = document.page(at: 0) else {
            coverImageView.image = nil
            coverImageView.isHidden = true
            return
        }

        coverImageView.image = firstPage.thumbnail(of: CGSize(width: 56, height: 76), for: .cropBox)
        coverImageView.isHidden = false
    }

    func openDocument(_ url: URL) {
        loadDocument(url)
    }

    @objc private func openPDFInCurrentDirectory() {
        guard let url = currentFileURL else { return }
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.loadDocument(selectedURL)
        }
    }

    @objc private func zoomIn() {
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent + 10)
            return
        }
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8)
        updateZoomLabel()
        saveSession()
    }

    @objc private func zoomOut() {
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent - 10)
            return
        }
        pdfView.scaleFactor = max(pdfView.scaleFactor * 0.8, 0.1)
        updateZoomLabel()
        saveSession()
    }

    @objc private func applyZoomFromField() {
        guard currentDocumentKind == .pdf else {
            let raw = zoomField.stringValue
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "％", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let percent = Int(raw), percent > 0 else {
                updateZoomLabel()
                return
            }
            setWebZoom(percent)
            return
        }
        let raw = zoomField.stringValue
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(raw), percent > 0 else {
            updateZoomLabel()
            return
        }
        pdfView.scaleFactor = min(max(percent, 10), 800) / 100
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    @objc private func prevPage() {
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: -1)
            return
        }
        pdfView.goToPreviousPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    @objc private func nextPage() {
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: 1)
            return
        }
        pdfView.goToNextPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    private func setWebZoom(_ percent: Int) {
        webZoomPercent = min(max(percent, 60), 220)
        zoomField.stringValue = "\(webZoomPercent)%"
        webView.pageZoom = CGFloat(webZoomPercent) / 100
        saveWebProgress()
        window?.makeFirstResponder(webView)
    }

    private func scrollWebPage(direction: Int) {
        let sign = direction < 0 ? "-" : ""
        webView.evaluateJavaScript("window.scrollBy({top: \(sign)Math.max(240, window.innerHeight * 0.86), behavior: 'smooth'});")
    }

    @objc private func goToCover() {
        guard currentDocumentKind == .pdf else {
            webView.evaluateJavaScript("window.scrollTo({top:0, behavior:'smooth'});")
            return
        }
        guard let firstPage = pdfView.document?.page(at: 0) else { return }
        pdfView.go(to: firstPage)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    @objc private func showSearchOverlay() {
        searchOverlay.isHidden = false
        window?.makeFirstResponder(searchOverlay.searchField)
    }

    private func hideSearchOverlay() {
        searchOverlay.isHidden = true
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        pdfView.clearSelection()
        clearWebSearchSelection()
        window?.makeFirstResponder(pdfView)
    }

    private func performSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults.removeAll()
            searchResultIndex = 0
            lastSearchQuery = ""
            searchOverlay.setResultText("")
            pdfView.clearSelection()
            clearWebSearchSelection()
            return
        }
        guard currentDocumentKind == .pdf else {
            performWebSearch(query, backwards: false)
            return
        }
        guard let document = pdfView.document else {
            searchOverlay.setResultText("0 / 0")
            return
        }

        if query != lastSearchQuery {
            searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            searchResultIndex = 0
            lastSearchQuery = query
        } else if !searchResults.isEmpty {
            searchResultIndex = (searchResultIndex + 1) % searchResults.count
        }

        showCurrentSearchResult()
    }

    private func goToPreviousSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: true)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex - 1 + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    private func goToNextSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: false)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        showCurrentSearchResult()
    }

    private func showCurrentSearchResult() {
        guard !searchResults.isEmpty else {
            searchOverlay.setResultText("0 / 0")
            pdfView.clearSelection()
            return
        }

        let selection = searchResults[searchResultIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        goToVisibleSearchSelection(selection)
        updatePageLabel()
        saveSession()
        searchOverlay.setResultText("\(searchResultIndex + 1) / \(searchResults.count)")
    }

    private func goToVisibleSearchSelection(_ selection: PDFSelection) {
        guard let page = selection.pages.first else {
            pdfView.go(to: selection)
            return
        }

        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else {
            pdfView.go(to: selection)
            return
        }

        let pageBounds = page.bounds(for: pdfView.displayBox)
        let overlayClearance = searchOverlay.isHidden ? CGFloat(64) : CGFloat(150)
        let yOffset = overlayClearance / max(pdfView.scaleFactor, 0.1)
        let destinationY = min(pageBounds.maxY, selectionBounds.maxY + yOffset)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: max(pageBounds.minX, selectionBounds.minX), y: destinationY)
        )
        pdfView.go(to: destination)
    }

    private func performWebSearch(_ rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchOverlay.setResultText("")
            clearWebSearchSelection()
            return
        }

        let escapedQuery = jsStringLiteral(query)
        let script = """
        (() => {
          const query = \(escapedQuery);
          const found = window.find(query, false, \(backwards ? "true" : "false"), true, false, true, false);
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            const rect = selection.getRangeAt(0).getBoundingClientRect();
            window.scrollBy({ top: rect.top - 160, behavior: 'smooth' });
          }
          return found;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            let found = result as? Bool ?? false
            self?.searchOverlay.setResultText(found ? AppText.localized("找到", "Found") : "0 / 0")
        }
    }

    private func clearWebSearchSelection() {
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges();")
    }

    private func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }

    private func turnPageFromScroll(_ direction: EdgePagingPDFView.ScrollPageDirection) {
        guard currentDocumentKind == .pdf else { return }
        switch direction {
        case .previous:
            pdfView.goToPreviousPage(nil)
        case .next:
            pdfView.goToNextPage(nil)
        }
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    private func scrollCurrentPageToTop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let page = self.pdfView.currentPage else { return }
            let bounds = page.bounds(for: self.pdfView.displayBox)
            let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
            self.pdfView.go(to: destination)
        }
    }

    @objc private func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc private func pageChanged() {
        handlePDFPageChange()
    }

    private func handlePDFPageChange() {
        let newPageIndex = currentPageIndex()
        guard newPageIndex != lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
    }

    private func hideAIPanelForPageTurn() {
        cancelScheduledAICollapse()
        aiPanel.setSelectedText("")
        setAIPanelCollapsed(true, animated: true)
    }

    @objc private func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(selectedText)
        if selectedText.isEmpty {
            scheduleAICollapse()
        } else {
            cancelScheduledAICollapse()
            setAIPanelCollapsed(false, animated: true)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "scrollChanged" {
            guard currentDocumentKind != .pdf else { return }
            let progress = message.body as? Double ?? 0
            webScrollProgress = progress
            pageLabel.stringValue = "\(Int(round(progress * 100)))%"
            saveWebProgress()
            return
        }
        guard message.name == "selectionChanged" else { return }
        let text = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentWebSelectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(currentWebSelectedText)
        if currentWebSelectedText.isEmpty {
            scheduleAICollapse()
        } else {
            cancelScheduledAICollapse()
            setAIPanelCollapsed(false, animated: true)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        } else if let fragment = url.fragment, !fragment.isEmpty {
            webView.evaluateJavaScript("document.getElementById(\(jsStringLiteral(fragment)))?.scrollIntoView({behavior:'smooth', block:'start'});")
        }
        decisionHandler(.cancel)
    }

    private func markSelectionIfWord(_ selection: PDFSelection?, text: String) {
        guard shouldPersistHighlight(for: text), let selection = selection else { return }

        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        for lineSelection in selections {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let pageIndex = pdfView.document?.index(for: page) ?? -1
                let key = "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
                guard !highlightedSelectionKeys.contains(key) else { continue }
                highlightedSelectionKeys.insert(key)

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
                page.addAnnotation(annotation)
            }
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func contextForCurrentSelection(selectedText: String) -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else { return "" }

        guard currentDocumentKind == .pdf else {
            return sentenceContext(containing: normalizedSelection, in: currentWebPlainText)
                ?? characterWindowContext(containing: normalizedSelection, in: currentWebPlainText, radius: 80)
                ?? ""
        }

        if let selection = pdfView.currentSelection,
           let page = selection.pages.first {
            let pageText = page.string ?? ""
            if let context = sentenceContext(containing: normalizedSelection, in: pageText) {
                return context
            }

            let bounds = selection.bounds(for: page)
            let expandedBounds = bounds.insetBy(dx: -120, dy: -36)
            if let nearbyText = page.selection(for: expandedBounds)?.string,
               let context = sentenceContext(containing: normalizedSelection, in: nearbyText) ?? characterWindowContext(containing: normalizedSelection, in: nearbyText, radius: 20) {
                return context
            }
        }

        let currentPageText = pdfView.currentPage?.string ?? ""
        return characterWindowContext(containing: normalizedSelection, in: currentPageText, radius: 20) ?? ""
    }

    private func sentenceContext(containing selectedText: String, in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let sentenceStart = normalizedText[..<range.lowerBound].lastIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.startIndex
        let sentenceEnd = normalizedText[range.upperBound...].firstIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.endIndex
        let sentence = normalizeWhitespace(String(normalizedText[sentenceStart..<sentenceEnd]))
        guard sentence.count > normalizedSelection.count else { return nil }
        return sentence
    }

    private func characterWindowContext(containing selectedText: String, in text: String, radius: Int) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let prefixStart = normalizedText.index(range.lowerBound, offsetBy: -radius, limitedBy: normalizedText.startIndex) ?? normalizedText.startIndex
        let suffixEnd = normalizedText.index(range.upperBound, offsetBy: radius, limitedBy: normalizedText.endIndex) ?? normalizedText.endIndex
        return normalizeWhitespace(String(normalizedText[prefixStart..<suffixEnd]))
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldPersistHighlight(for text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 40 else { return false }
        guard normalized.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return normalized.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    func pdfViewWillChangeScaleFactor(_ sender: PDFView) {
        updateZoomLabel()
    }

    func pdfViewPageChanged(_ sender: PDFView) {
        handlePDFPageChange()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = true
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = false
            updateZoomLabel()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === zoomField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyZoomFromField()
            return true
        }
        return false
    }

    private func updateZoomLabel() {
        if isEditingZoomField { return }
        guard currentDocumentKind == .pdf else {
            zoomField.stringValue = "100%"
            return
        }
        zoomField.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    private func updatePageLabel() {
        guard currentDocumentKind == .pdf else {
            if pageLabel.stringValue == AppText.noPDF || pageLabel.stringValue == "EPUB" || pageLabel.stringValue == "DOCX" {
                pageLabel.stringValue = "0%"
            }
            return
        }
        guard let document = pdfView.document else {
            pageLabel.stringValue = AppText.noPDF
            return
        }
        guard let page = pdfView.currentPage else {
            pageLabel.stringValue = "1  /  \(document.pageCount)"
            return
        }
        pageLabel.stringValue = "\(document.index(for: page) + 1)  /  \(document.pageCount)"
    }

    private func currentPageIndex() -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page)
    }

    private func fileMD5(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func bookSessionKey(_ suffix: String) -> String? {
        guard let md5 = currentFileMD5 else { return nil }
        return "bookSession.\(md5).\(suffix)"
    }

    private func restoreWebProgressAfterLoad() {
        guard currentDocumentKind != .pdf, let progressKey = bookSessionKey("webProgress") else { return }
        let progress = min(max(UserDefaults.standard.double(forKey: progressKey), 0), 1)
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
        let percent = UserDefaults.standard.integer(forKey: bookSessionKey("webZoom") ?? "")
        if percent >= 60, percent <= 220 {
            webZoomPercent = percent
            zoomField.stringValue = "\(webZoomPercent)%"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.currentDocumentKind != .pdf else { return }
            self.webView.pageZoom = CGFloat(self.webZoomPercent) / 100
            self.zoomField.stringValue = "\(self.webZoomPercent)%"
            self.webView.evaluateJavaScript("""
            (() => {
              const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
              window.scrollTo(0, height * \(progress));
            })();
            """)
        }
    }

    private func saveWebProgress() {
        guard !isRestoringSession, currentDocumentKind != .pdf else { return }
        guard let progressKey = bookSessionKey("webProgress"), let zoomKey = bookSessionKey("webZoom") else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWebProgressSave) > 0.5 else { return }
        lastWebProgressSave = now
        UserDefaults.standard.set(webScrollProgress, forKey: progressKey)
        UserDefaults.standard.set(webZoomPercent, forKey: zoomKey)
    }

    private func restoreBookProgressOrGoHome() {
        guard let document = pdfView.document else { return }
        guard
            let pageKey = bookSessionKey("pageIndex"),
            let scaleKey = bookSessionKey("scale"),
            UserDefaults.standard.object(forKey: pageKey) != nil
        else {
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
            }
            pdfView.autoScales = true
            return
        }

        let pageIndex = UserDefaults.standard.integer(forKey: pageKey)
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        } else if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
        }

        let scale = UserDefaults.standard.double(forKey: scaleKey)
        if scale >= 0.1, scale <= 8 {
            pdfView.scaleFactor = scale
        }
    }

    private func saveSession() {
        if isRestoringSession { return }
        guard let url = currentFileURL else { return }
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        UserDefaults.standard.set(bookmark, forKey: "lastPDFBookmark")
        guard currentDocumentKind == .pdf else {
            saveWebProgress()
            return
        }
        let pageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        if let pageKey = bookSessionKey("pageIndex"), let scaleKey = bookSessionKey("scale") {
            UserDefaults.standard.set(pageIndex, forKey: pageKey)
            UserDefaults.standard.set(pdfView.scaleFactor, forKey: scaleKey)
        }
    }

    private func restoreSession() {
        guard let bookmark = UserDefaults.standard.data(forKey: "lastPDFBookmark"), !bookmark.isEmpty else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale else { return }

        isRestoringSession = true
        loadDocument(url)
        isRestoringSession = false
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    private func installKeyboardPagingMonitor() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.window else { return event }
            guard self.handlePageKey(event) else { return event }
            return nil
        }
    }

    private func handlePageKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            showSearchOverlay()
            return true
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        guard !isEditingTextInput else { return false }

        switch event.keyCode {
        case 123:
            prevPage()
            return true
        case 124:
            nextPage()
            return true
        default:
            return false
        }
    }

    private var isEditingTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}
