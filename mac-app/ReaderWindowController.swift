import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

final class ClickEditableTextField: NSTextField {
    private var allowsEditingFocus = false

    override var acceptsFirstResponder: Bool {
        allowsEditingFocus || currentEditor() != nil
    }

    override func mouseDown(with event: NSEvent) {
        allowsEditingFocus = true
        defer { allowsEditingFocus = false }
        super.mouseDown(with: event)
    }
}

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    private static let minimumReadablePDFScale: CGFloat = 1.0
    private static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")

    private var pdfView: EdgePagingPDFView!
    private var webView: WKWebView!
    private let contentArea = NSView()
    private let pdfContainer = ClippingView()
    private let pdfDimOverlay = PassthroughOverlayView()
    private let aiPanel = AIChatPanel()
    private let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    private let resizeHandle = ResizeHandleView()
    private let titleLabel = NSTextField(labelWithString: "Leaf Reader")
    private let coverImageView = NSImageView()
    private let pageLabel = ClickEditableTextField(string: AppText.noPDF)
    private let zoomField = ClickEditableTextField(string: "100%")
    private let searchOverlay = SearchOverlayView()
    private var fullScreenButton: NSButton!
    private var coverButton: NSButton!
    private var tocButton: NSButton!
    private var recentButton: NSButton!
    private var vocabularyButton: NSButton!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var searchButton: NSButton!
    private var searchUnderlineButton: SearchUnderlineButton!
    private weak var toolbarView: NSView?
    private weak var bottomBarView: NSView?
    private weak var zoomGroupView: NSView?
    private var currentFileURL: URL?
    private var currentFileMD5: String?
    private var sessionStore = ReaderSessionStore(fileMD5: nil)
    private var currentDocumentKind: ReaderDocumentKind = .pdf
    private var currentWebPlainText = ""
    private var currentWebSelectedText = ""
    private var currentWebSelectionContext = ""
    private var currentTOCItems: [ReaderTOCItem] = []
    private var pdfTOCDestinations: [String: PDFDestination] = [:]
    private var webZoomPercent = 100
    private var webScrollProgress: Double = 0
    private var lastWebProgressSave = Date.distantPast
    private var accumulatedPDFTrackpadScroll: CGFloat = 0
    private var lastPDFTrackpadPageTurn = Date.distantPast
    private var didTurnPageForCurrentPDFTrackpadGesture = false
    private var lastPageIndex: Int?
    private var searchResults: [PDFSelection] = []
    private var searchResultIndex = 0
    private var lastSearchQuery = ""
    private var pdfAgentIndex: PDFDocumentAgentIndex?
    private var pdfEmbeddingStore = PDFEmbeddingStore()
    private let embeddingClient = EmbeddingClient()
    private let retrievalQueryClient = AIClient()
    private var isPreparingPDFEmbeddings = false
    private var suppressSearchSelectionForAIUntil = Date.distantPast
    private var highlightedSelectionKeys = Set<String>()
    private var storedWordRecords: [StoredPDFWordRecord] = []
    private var pdfWordRecordStore: PDFWordRecordStore?
    private var storedWebWordRecords: [StoredWebWordRecord] = []
    private var webWordRecordStore: WebWordRecordStore?
    private var didRegisterSelectionObserver = false
    private var isRestoringSession = false
    private var isEditingZoomField = false
    private var isEditingPageField = false
    private var isAIPanelCollapsed = true
    private var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    private var aiSettingsPanelController: AISettingsPanelController?
    private var recentDocumentsPanelController: RecentDocumentsPanelController?
    private var aiHandleLeadingConstraint: NSLayoutConstraint!
    private var aiPanelWidthConstraint: NSLayoutConstraint!
    private var localEventMonitor: Any?

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
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
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
        userContentController.add(self, name: "webWordClicked")
        userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              var lastScrollSent = 0;
              var preservedHighlightRange = null;
              var documentMouseDown = false;
              const installSelectionHighlightStyle = () => {
                if (document.getElementById('leaf-reader-selection-highlight-style')) return;
                const style = document.createElement('style');
                style.id = 'leaf-reader-selection-highlight-style';
                style.textContent = `
                  ::highlight(leaf-reader-selection) { background: rgba(255, 221, 87, .62); color: inherit; }
                  .leaf-reader-selection-highlight { background: rgba(255, 221, 87, .62); color: inherit; }
                  .leaf-reader-linked-word { background: rgba(255, 221, 87, .62); border-radius: 3px; cursor: pointer; }
                `;
                document.head.appendChild(style);
              };
              window.leafReaderFindTextRange = (word, context) => {
                const normalizedWord = String(word || '').replace(/\\s+/g, ' ').trim().toLowerCase();
                const normalizedContext = String(context || '').replace(/\\s+/g, ' ').trim().toLowerCase();
                if (!normalizedWord) return null;
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  const value = node.nodeValue || '';
                  const lower = value.toLowerCase();
                  let index = lower.indexOf(normalizedWord);
                  while (index >= 0) {
                    const block = node.parentElement?.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div');
                    const source = (block ? (block.innerText || block.textContent || '') : value).replace(/\\s+/g, ' ').trim().toLowerCase();
                    if (!normalizedContext || source.includes(normalizedContext.slice(0, Math.min(80, normalizedContext.length)))) {
                      const range = document.createRange();
                      range.setStart(node, index);
                      range.setEnd(node, index + normalizedWord.length);
                      return range;
                    }
                    index = lower.indexOf(normalizedWord, index + normalizedWord.length);
                  }
                }
                return null;
              };
              window.leafReaderRestoreWordHighlights = (records) => {
                installSelectionHighlightStyle();
                document.querySelectorAll('span.leaf-reader-linked-word').forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
                for (const record of records || []) {
                  try {
                    const range = window.leafReaderFindTextRange(record.word, record.context);
                    if (!range) continue;
                    const span = document.createElement('span');
                    span.className = 'leaf-reader-linked-word';
                    span.dataset.leafWordId = record.id;
                    range.surroundContents(span);
                  } catch (_) {}
                }
              };
              window.leafReaderScrollToWord = (id, fallbackProgress) => {
                const target = document.querySelector(`span.leaf-reader-linked-word[data-leaf-word-id="${CSS.escape(String(id || ''))}"]`);
                if (target) {
                  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  return true;
                }
                const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo({ top: height * Math.max(0, Math.min(1, Number(fallbackProgress || 0))), behavior: 'smooth' });
                return false;
              };
              const clearSpanHighlights = () => {
                document.querySelectorAll('span.leaf-reader-selection-highlight').forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) parent.insertBefore(span.firstChild, span);
                  parent.removeChild(span);
                  parent.normalize();
                });
              };
              const clearPreservedSelectionHighlight = () => {
                preservedHighlightRange = null;
                if (window.CSS && CSS.highlights) CSS.highlights.delete('leaf-reader-selection');
                clearSpanHighlights();
              };
              const preserveSelectionHighlight = (selection) => {
                if (!selection || selection.rangeCount === 0 || String(selection || "").trim().length === 0) return;
                installSelectionHighlightStyle();
                clearPreservedSelectionHighlight();
                const range = selection.getRangeAt(0).cloneRange();
                preservedHighlightRange = range;
                if (window.CSS && CSS.highlights && window.Highlight) {
                  CSS.highlights.set('leaf-reader-selection', new Highlight(range));
                  return;
                }
                try {
                  const span = document.createElement('span');
                  span.className = 'leaf-reader-selection-highlight';
                  range.surroundContents(span);
                } catch (_) {
                  // Complex cross-node EPUB selections still keep their text context in native selection.
                }
              };
              const sendSelection = () => {
                const selection = window.getSelection();
                const text = String(selection || "").trim();
                let context = "";
                if (selection && selection.rangeCount > 0 && text.length > 0) {
                  preserveSelectionHighlight(selection);
                  const container = selection.getRangeAt(0).commonAncestorContainer;
                  const element = container.nodeType === Node.ELEMENT_NODE ? container : container.parentElement;
                  const block = element ? element.closest('p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div') : null;
                  const source = block ? (block.innerText || block.textContent || "") : text;
                  context = source.replace(/\\s+/g, " ").trim().slice(0, 360);
                } else if (documentMouseDown) {
                  clearPreservedSelectionHighlight();
                }
                window.webkit.messageHandlers.selectionChanged.postMessage({ text, context });
                documentMouseDown = false;
              };
              const sendScroll = (force = false) => {
                const now = Date.now();
                if (!force && now - lastScrollSent < 200) return;
                lastScrollSent = now;
                const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                const progress = Math.max(0, Math.min(1, window.scrollY / height));
                window.webkit.messageHandlers.scrollChanged.postMessage(progress);
              };
              document.addEventListener("mousedown", () => {
                documentMouseDown = true;
                clearPreservedSelectionHighlight();
                const selection = window.getSelection();
                if (selection) selection.removeAllRanges();
                window.webkit.messageHandlers.selectionChanged.postMessage({ text: "", context: "" });
              });
              document.addEventListener("click", (event) => {
                const target = event.target?.closest?.('span.leaf-reader-linked-word');
                if (!target) return;
                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.webWordClicked.postMessage(String(target.dataset.leafWordId || ''));
              }, true);
              document.addEventListener("selectionchange", () => setTimeout(sendSelection, 0));
              document.addEventListener("mouseup", () => {
                sendSelection();
              });
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

        pageLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
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
        searchUnderlineButton = SearchUnderlineButton(title: "", target: self, action: #selector(showSearchOverlay))
        searchUnderlineButton.toolTip = AppText.localized("搜索文档", "Search document")
        searchUnderlineButton.isDark = ReaderTheme.selected == .dark
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索文档", "Search document")

        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        tocButton = capsuleButton(title: AppText.localized("目录", "TOC"), symbol: "list.bullet", action: #selector(showTableOfContents))
        recentButton = capsuleButton(title: AppText.localized("最近", "Recent"), symbol: "clock.arrow.circlepath", action: #selector(showRecentDocuments))
        vocabularyButton = capsuleButton(title: AppText.localized("单词本", "Words"), symbol: "text.book.closed", action: #selector(showVocabularyBook))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)

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

        for view in [openButton, titleLabel, coverImageView, zoomGroup, pageLabel, searchUnderlineButton!, searchButton!, fullScreenButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        for view in [settingsButton, recentButton!, vocabularyButton!, tocButton!, coverButton!, prevButton!, nextButton!] {
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

            openButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 112),
            openButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 24),
            openButton.heightAnchor.constraint(equalToConstant: 24),

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

            searchUnderlineButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 6),
            searchUnderlineButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchUnderlineButton.widthAnchor.constraint(equalToConstant: 74),
            searchUnderlineButton.heightAnchor.constraint(equalToConstant: 28),

            searchButton.leadingAnchor.constraint(equalTo: searchUnderlineButton.trailingAnchor, constant: 2),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 76),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 30),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: 560),
            searchOverlay.heightAnchor.constraint(equalToConstant: 70),

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
            nextButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.setAIPanelCollapsed(true, animated: false)
        }
        applyReaderTheme()
        restoreSession()
    }

    private func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        setSystemImage(symbol, on: button)
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
        let button = CapsuleChromeButton(title: title, target: self, action: action)
        button.identifier = Self.capsuleButtonIdentifier
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 13)
        button.isDark = ReaderTheme.selected == .dark
        return button
    }

    private func setSystemImage(_ symbol: String, on button: NSButton, accessibilityDescription: String? = nil) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
        if button.image == nil, button.title.isEmpty {
            button.title = accessibilityDescription ?? ""
        }
    }

    private func capsuleAttributedTitle(_ title: String, isDark: Bool) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: isDark
                    ? NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
                    : NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            ]
        )
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
        tocButton.title = AppText.localized("目录", "TOC")
        recentButton.title = AppText.localized("最近", "Recent")
        vocabularyButton.title = AppText.localized("单词本", "Words")
        prevButton.title = AppText.prev
        nextButton.title = AppText.next
        for button in [coverButton, tocButton, recentButton, vocabularyButton, prevButton, nextButton] {
            if let capsule = button as? CapsuleChromeButton {
                capsule.isDark = ReaderTheme.selected == .dark
            }
        }
        if pdfView.document == nil {
            pageLabel.stringValue = AppText.noPDF
        }
        fullScreenButton.image = NSImage(
            systemSymbolName: window?.styleMask.contains(.fullScreen) == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
    }

    private func applyReaderTheme() {
        let isDark = ReaderTheme.selected == .dark
        let chromeBackground = isDark
            ? NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            : NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)

        window?.backgroundColor = chromeBackground
        window?.appearance = isDark ? NSAppearance(named: .darkAqua) : nil
        contentArea.layer?.backgroundColor = chromeBackground.cgColor
        pdfContainer.layer?.backgroundColor = chromeBackground.cgColor
        webView.layer?.backgroundColor = chromeBackground.cgColor
        toolbarView?.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
            : NSColor.white.withAlphaComponent(0.97)
        ).cgColor
        toolbarView?.layer?.borderColor = (isDark
            ? NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
            : NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1)
        ).cgColor
        bottomBarView?.layer?.backgroundColor = toolbarView?.layer?.backgroundColor
        bottomBarView?.layer?.borderColor = toolbarView?.layer?.borderColor
        zoomGroupView?.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
            : NSColor.white
        ).cgColor
        zoomGroupView?.layer?.borderColor = (isDark
            ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            : NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1)
        ).cgColor
        resizeHandle.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
            : NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
        ).cgColor
        searchUnderlineButton?.isDark = isDark
        applyChromeTheme(to: window?.contentView, isDark: isDark)
        aiPanel.setDarkMode(isDark)
        searchOverlay.setDarkMode(isDark)
        pdfView.backgroundColor = chromeBackground
        pdfView.enclosingScrollView?.backgroundColor = chromeBackground
        pdfView.documentView?.wantsLayer = true
        pdfView.documentView?.layer?.backgroundColor = chromeBackground.cgColor
        applyPDFReaderTheme(isDark: isDark)

        applyWebReaderTheme()
    }

    private func applyChromeTheme(to view: NSView?, isDark: Bool) {
        guard let view else { return }
        let textColor = isDark
            ? NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        let secondaryColor = isDark
            ? NSColor(red: 0.62, green: 0.67, blue: 0.74, alpha: 1)
            : NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)

        if let label = view as? NSTextField {
            label.textColor = textColor
        }
        if let button = view as? NSButton {
            if button.identifier == Self.capsuleButtonIdentifier {
                (button as? CapsuleChromeButton)?.isDark = isDark
            } else {
                button.contentTintColor = secondaryColor
            }
        }
        if view !== aiPanel, view !== searchOverlay {
            for subview in view.subviews {
                applyChromeTheme(to: subview, isDark: isDark)
            }
        }
    }

    private func applyPDFReaderTheme(isDark: Bool) {
        guard let documentView = pdfView.documentView else { return }
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.clear.cgColor
        documentView.layer?.filters = []
        pdfDimOverlay.isHidden = !isDark || currentDocumentKind != .pdf
        pdfDimOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
        documentView.needsDisplay = true
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func applyWebReaderTheme() {
        guard webView != nil else { return }
        let darkCSS = """
        html.leaf-reader-dark { background: #111418 !important; color-scheme: dark; }
        html.leaf-reader-dark body {
          color: #d9dee7 !important;
          background: #171a20 !important;
        }
        html.leaf-reader-dark p,
        html.leaf-reader-dark div,
        html.leaf-reader-dark span,
        html.leaf-reader-dark li,
        html.leaf-reader-dark blockquote,
        html.leaf-reader-dark td,
        html.leaf-reader-dark th,
        html.leaf-reader-dark h1,
        html.leaf-reader-dark h2,
        html.leaf-reader-dark h3,
        html.leaf-reader-dark h4,
        html.leaf-reader-dark h5,
        html.leaf-reader-dark h6,
        html.leaf-reader-dark strong,
        html.leaf-reader-dark em,
        html.leaf-reader-dark b,
        html.leaf-reader-dark i {
          color: #d9dee7 !important;
          background-color: transparent !important;
          text-shadow: none !important;
        }
        html.leaf-reader-dark body * {
          border-color: #343b46 !important;
        }
        html.leaf-reader-dark a {
          color: #9fc0ff !important;
        }
        html.leaf-reader-dark img,
        html.leaf-reader-dark svg {
          filter: brightness(.88) contrast(.98);
        }
        html.leaf-reader-dark ::selection {
          background: rgba(255, 221, 87, .46) !important;
        }
        """
        let cssLiteral = jsStringLiteral(darkCSS)
        let enabled = ReaderTheme.selected == .dark ? "true" : "false"
        webView.evaluateJavaScript("""
        (() => {
          const enabled = \(enabled);
          let style = document.getElementById('leaf-reader-theme-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'leaf-reader-theme-style';
            document.head.appendChild(style);
          }
          style.textContent = \(cssLiteral);
          document.documentElement.classList.toggle('leaf-reader-dark', enabled);
        })();
        """)
    }

    @objc private func openAISettings() {
        guard let window else { return }
        let controller = AISettingsPanelController()
        controller.onSaved = { [weak self] in
            self?.refreshLanguageUI()
            self?.applyReaderTheme()
        }
        aiSettingsPanelController = controller
        controller.show(attachedTo: window)
    }

    @objc private func toggleAIPanel() {
        setAIPanelCollapsed(!isAIPanelCollapsed, animated: true)
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
        panel.allowedContentTypes = [.pdf, .epub, .init(filenameExtension: "docx")].compactMap { $0 }
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
        sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
        pdfWordRecordStore = currentFileMD5.map { PDFWordRecordStore(fileMD5: $0) }
        webWordRecordStore = nil
        currentWebPlainText = ""
        currentWebSelectedText = ""
        pdfAgentIndex = nil
        let toc = ReaderTOCHelper.pdfTOCItems(from: document, displayBox: pdfView.displayBox)
        currentTOCItems = toc.items
        pdfTOCDestinations = toc.destinations
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        highlightedSelectionKeys.removeAll()
        storedWordRecords = loadStoredWordRecords()
        storedWebWordRecords.removeAll()
        restoreStoredWordAnnotations()
        aiPanel.loadLinkedWordBubbles(pdfWordRecordStore?.linkedWordBubbles(from: storedWordRecords) ?? [])
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
        applyReaderTheme()
        updatePageLabel()
        updateZoomLabel()
        RecentDocumentsStore.record(url: url, kind: .pdf)
        saveSession()
    }

    private func loadWebDocument(_ url: URL, kind: ReaderDocumentKind) {
        do {
            let document = try WebDocumentLoader.load(url: url)
            currentDocumentKind = kind
            pdfView.isHidden = true
            pdfDimOverlay.isHidden = true
            webView.isHidden = false
            pdfView.document = nil
            currentFileURL = url
            currentFileMD5 = fileMD5(for: url)
            sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
            pdfWordRecordStore = nil
            webWordRecordStore = currentFileMD5.map { WebWordRecordStore(fileMD5: $0) }
            pdfAgentIndex = nil
            currentWebPlainText = document.plainText
            currentWebSelectedText = ""
            currentWebSelectionContext = ""
            currentTOCItems = document.tocItems
            pdfTOCDestinations = [:]
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            webZoomPercent = 100
            webScrollProgress = 0
            highlightedSelectionKeys.removeAll()
            storedWordRecords.removeAll()
            storedWebWordRecords = loadStoredWebWordRecords()
            aiPanel.loadLinkedWordBubbles(webWordRecordStore?.linkedWordBubbles(from: storedWebWordRecords) ?? [])
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
            applyReaderTheme()
            applyWebZoomToPage()
            restoreWebProgressAfterLoad()
            RecentDocumentsStore.record(url: url, kind: kind)
            saveSession()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showTableOfContents() {
        guard !currentTOCItems.isEmpty else {
            NSSound.beep()
            return
        }

        let menu = NSMenu()
        for (index, item) in currentTOCItems.prefix(120).enumerated() {
            let indent = String(repeating: "  ", count: min(item.level, 4))
            let menuItem = NSMenuItem(title: "\(indent)\(item.title)", action: #selector(selectTableOfContentsItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = index
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: tocButton.bounds.height + 4), in: tocButton)
    }

    @objc private func showRecentDocuments() {
        let items = RecentDocumentsStore.load()
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let controller = RecentDocumentsPanelController()
        recentDocumentsPanelController = controller
        controller.show(
            items: items,
            attachedTo: window,
            onOpen: { [weak self] path in
                self?.loadDocument(URL(fileURLWithPath: path))
            },
            onClear: {
                RecentDocumentsStore.clear()
            },
            onClose: { [weak self] in
                self?.recentDocumentsPanelController = nil
            }
        )
    }

    @objc private func showVocabularyBook() {
        let records: [(word: String, answer: String, location: String)]
        if currentDocumentKind == .pdf {
            records = storedWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ($0.word, $0.answer, AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)")) }
        } else {
            records = storedWebWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ($0.word, $0.answer, AppText.localized("网页", "Web")) }
        }
        guard !records.isEmpty else {
            NSSound.beep()
            return
        }

        let content = records.prefix(80).map { record in
            "• \(record.word)  \(record.location)\n\(String(record.answer.prefix(180)))"
        }.joined(separator: "\n\n")
        let alert = NSAlert()
        alert.messageText = AppText.localized("本书单词本", "Book Vocabulary")
        alert.informativeText = content
        alert.addButton(withTitle: AppText.confirm)
        alert.runModal()
    }

    @objc private func selectTableOfContentsItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, currentTOCItems.indices.contains(index) else { return }
        let item = currentTOCItems[index]
        if currentDocumentKind == .pdf {
            jumpToPDFTOCItem(item)
        } else {
            jumpToWebTOCItem(item)
        }
    }

    private func jumpToPDFTOCItem(_ item: ReaderTOCItem) {
        guard let destination = pdfTOCDestinations[item.href],
              let page = destination.page,
              let pageIndex = pdfView.document?.index(for: page) else {
            return
        }

        clearAISelectionForNavigation()
        pdfView.go(to: destination)
        lastPageIndex = pageIndex
        updatePageLabel()
        saveSession()
    }

    private func jumpToWebTOCItem(_ item: ReaderTOCItem) {
        webView.evaluateJavaScript(ReaderTOCHelper.webJumpScript(for: item))
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
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8)
        updateZoomLabel()
        saveSession()
    }

    @objc private func zoomOut() {
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent - 10)
            return
        }
        pdfView.autoScales = false
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
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(percent, 10), 800) / 100
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    @objc private func applyPageFromField() {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              document.pageCount > 0 else {
            updatePageLabel()
            window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
            return
        }

        let raw = pageLabel.stringValue
        let pageNumberText: String
        if let range = raw.range(of: #"\d+"#, options: .regularExpression) {
            pageNumberText = String(raw[range])
        } else {
            pageNumberText = ""
        }
        guard let requestedPage = Int(pageNumberText) else {
            updatePageLabel()
            window?.makeFirstResponder(pdfView)
            return
        }

        let targetIndex = min(max(requestedPage, 1), document.pageCount) - 1
        guard let page = document.page(at: targetIndex) else {
            updatePageLabel()
            window?.makeFirstResponder(pdfView)
            return
        }

        clearAISelectionForNavigation()
        pdfView.go(to: page)
        lastPageIndex = targetIndex
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    @objc private func prevPage() {
        clearAISelectionForNavigation()
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
        clearAISelectionForNavigation()
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
        applyWebZoomToPage()
        saveWebProgress()
        window?.makeFirstResponder(webView)
    }

    private func applyWebZoomToPage() {
        guard webView != nil else { return }
        webView.pageZoom = 1
        webView.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(webZoomPercent) / 100)');
        """)
    }

    private func scrollWebPage(direction: Int) {
        let sign = direction < 0 ? "-" : ""
        webView.evaluateJavaScript("window.scrollBy({top: \(sign)Math.max(240, window.innerHeight * 0.86), behavior: 'smooth'});")
    }

    @objc private func goToCover() {
        clearAISelectionForNavigation()
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
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
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
            clearSearchSelectionForAI()
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
            clearSearchSelectionForAI()
            return
        }

        let selection = searchResults[searchResultIndex]
        beginSuppressingSearchSelectionForAI()
        pdfView.setCurrentSelection(selection, animate: true)
        let pageIndex = goToVisibleSearchSelection(selection)
        if let pageIndex {
            lastPageIndex = pageIndex
        }
        updatePageLabel()
        saveSession()
        searchOverlay.setResultText("\(searchResultIndex + 1) / \(searchResults.count)")
        clearSearchSelectionForAI()
    }

    @discardableResult
    private func goToVisibleSearchSelection(_ selection: PDFSelection) -> Int? {
        guard let page = selection.pages.first else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        pdfView.go(to: page)
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let overlayClearance = searchOverlay.isHidden ? CGFloat(64) : CGFloat(150)
        let yOffset = overlayClearance / max(pdfView.scaleFactor, 0.1)
        let destinationY = min(pageBounds.maxY, selectionBounds.maxY + yOffset)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: max(pageBounds.minX, selectionBounds.minX), y: destinationY)
        )
        pdfView.go(to: destination)
        return pdfView.document?.index(for: page)
    }

    private func performWebSearch(_ rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchOverlay.setResultText("")
            clearWebSearchSelection()
            clearSearchSelectionForAI()
            return
        }

        beginSuppressingSearchSelectionForAI()
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
            self?.clearSearchSelectionForAI()
        }
    }

    private func beginSuppressingSearchSelectionForAI() {
        suppressSearchSelectionForAIUntil = Date().addingTimeInterval(1.2)
    }

    private func clearSearchSelectionForAI() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        aiPanel.clearSelectedText()
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
        clearAISelectionForNavigation()
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

    private func clearAISelectionForNavigation() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        aiPanel.clearSelectedText()

        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
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

    @objc private func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }
        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(selectedText)
        if !selectedText.isEmpty {
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
        if message.name == "webWordClicked" {
            guard currentDocumentKind != .pdf,
                  let linkID = message.body as? String,
                  !linkID.isEmpty else {
                return
            }
            selectStoredLinkedWord(linkID: linkID)
            return
        }
        guard message.name == "selectionChanged" else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }
        let text: String
        let context: String
        if let payload = message.body as? [String: Any] {
            text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            context = (payload["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            text = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            context = ""
        }
        currentWebSelectedText = text.count > 1 ? text : ""
        currentWebSelectionContext = currentWebSelectedText.isEmpty ? "" : context
        aiPanel.setSelectedText(currentWebSelectedText)
        if !currentWebSelectedText.isEmpty {
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard currentDocumentKind != .pdf else { return }
        applyWebReaderTheme()
        restoreStoredWebWordHighlights()
        applyWebZoomToPage()
        zoomField.stringValue = "\(webZoomPercent)%"
    }

    private func persistSelectedWordIfNeeded(_ selection: PDFSelection?, text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              let selection,
              let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }

        let bounds = selection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            return existing.id
        }

        let record = StoredPDFWordRecord(
            id: UUID().uuidString,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            question: "\(AppText.explainPrefix): \(text.trimmingCharacters(in: .whitespacesAndNewlines))",
            answer: "",
            createdAt: Date()
        )
        storedWordRecords.append(record)
        addStoredWordAnnotation(record)
        saveStoredWordRecords()
        return record.id
    }

    private func persistSelectedWebWordIfNeeded(text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = currentWebSelectionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = webWordRecordStore?.existingRecord(in: storedWebWordRecords, word: word, context: context) {
            return existing.id
        }

        let record = StoredWebWordRecord(
            id: UUID().uuidString,
            word: word,
            context: context,
            scrollProgress: webScrollProgress,
            question: "\(AppText.explainPrefix): \(word)",
            answer: "",
            createdAt: Date()
        )
        storedWebWordRecords.append(record)
        saveStoredWebWordRecords()
        restoreStoredWebWordHighlights()
        return record.id
    }

    private func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWordRecords[index].question = question
            storedWordRecords[index].answer = answer
            saveStoredWordRecords()
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWebWordRecords[index].question = question
            storedWebWordRecords[index].answer = answer
            saveStoredWebWordRecords()
        }
    }

    private func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        for record in storedWordRecords {
            addStoredWordAnnotation(record)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return }
        let key = pdfWordRecordStore?.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            ?? "\(record.pageIndex):\(Int(record.bounds.x.rounded())):\(Int(record.bounds.y.rounded())):\(Int(record.bounds.width.rounded())):\(Int(record.bounds.height.rounded()))"
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: record.bounds.cgRect, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
    }

    private func restoreStoredWebWordHighlights() {
        guard currentDocumentKind != .pdf, !storedWebWordRecords.isEmpty else { return }
        let payload = storedWebWordRecords.map {
            [
                "id": $0.id,
                "word": $0.word,
                "context": $0.context
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreWordHighlights(\(json));")
    }

    private func contextForCurrentSelection(selectedText: String) -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else { return "" }

        guard currentDocumentKind == .pdf else {
            if !currentWebSelectionContext.isEmpty {
                return ReaderAIContextBuilder.selectedTextContext(
                    selectedText: normalizedSelection,
                    sourceText: currentWebSelectionContext,
                    radius: 40
                )
                    ?? currentWebSelectionContext
            }
            return ReaderAIContextBuilder.selectedTextContext(
                selectedText: normalizedSelection,
                sourceText: currentWebPlainText,
                radius: 40
            ) ?? ""
        }

        if let selection = pdfView.currentSelection,
           let page = selection.pages.first {
            let pageText = page.string ?? ""
            if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: pageText, radius: 20) {
                return context
            }

            let bounds = selection.bounds(for: page)
            let expandedBounds = bounds.insetBy(dx: -120, dy: -36)
            if let nearbyText = page.selection(for: expandedBounds)?.string,
               let context = ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: nearbyText, radius: 20) {
                return context
            }
        }

        let currentPageText = pdfView.currentPage?.string ?? ""
        return ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: currentPageText, radius: 20) ?? ""
    }

    private func currentSummaryContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        let title = titleLabel.stringValue
        if currentDocumentKind == .pdf {
            let text = ReaderAIContextBuilder.normalizeWhitespace(currentPDFPageSummaryText())
            completion(text.isEmpty ? nil : (title, String(text.prefix(6000))))
            return
        }

        currentWebVisibleText { [weak self] visibleText in
            guard let self else {
                completion(nil)
                return
            }
            if !visibleText.isEmpty {
                completion((title, String(visibleText.prefix(6000))))
                return
            }

            let fallback = self.currentWebProgressTextWindow()
            completion(fallback.isEmpty ? nil : (title, fallback))
        }
    }

    private func currentTranslationContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        let title = titleLabel.stringValue
        if currentDocumentKind == .pdf {
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFPageTranslationText())
            completion(text.isEmpty ? nil : (title, String(text.prefix(9000))))
            return
        }

        currentWebVisibleText(preserveLineBreaks: true) { [weak self] visibleText in
            guard let self else {
                completion(nil)
                return
            }
            if !visibleText.isEmpty {
                completion((title, String(visibleText.prefix(9000))))
                return
            }

            let fallback = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(self.currentWebProgressTextWindow())
            completion(fallback.isEmpty ? nil : (title, fallback))
        }
    }

    private func currentReadingQuestionContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        let title = titleLabel.stringValue
        if currentDocumentKind == .pdf {
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFPageTranslationText())
            completion(text.isEmpty ? nil : (title, String(text.prefix(5000))))
            return
        }

        currentWebVisibleText(preserveLineBreaks: true) { [weak self] visibleText in
            guard let self else {
                completion(nil)
                return
            }
            if !visibleText.isEmpty {
                completion((title, String(visibleText.prefix(5000))))
                return
            }

            let fallback = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(self.currentWebProgressTextWindow())
            completion(fallback.isEmpty ? nil : (title, String(fallback.prefix(5000))))
        }
    }

    private func documentAgentPrompt(question: String, context: String, completion: @escaping (String?) -> Void) {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document else {
            completion(nil)
            return
        }

        if pdfAgentIndex == nil {
            pdfAgentIndex = PDFDocumentAgentIndex(document: document, title: titleLabel.stringValue)
        }

        let currentPageText = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFPageTranslationText())
        let chapterText = currentPDFNearbyPagesText()
        crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: currentPageText) { [weak self] retrievalQuery in
            DispatchQueue.main.async {
                guard let self else {
                    completion(nil)
                    return
                }
                let combinedRetrievalQuestion = [question, retrievalQuery]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let retrievalQuestion = combinedRetrievalQuestion.isEmpty ? question : combinedRetrievalQuestion
                self.preparePDFEmbeddingsIfPossible()
                self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                    DispatchQueue.main.async {
                        guard let self else {
                            completion(nil)
                            return
                        }
                        let evidence = self.pdfAgentIndex?.search(
                            question: retrievalQuestion,
                            currentPageIndex: self.currentPageIndex(),
                            queryEmbedding: queryEmbedding
                        ) ?? []
                        self.appendEvidenceBubbles(evidence)
                        completion(AIPromptStore.documentAgentPrompt(
                            title: self.documentTitleForAI(),
                            question: question,
                            currentPageText: String(currentPageText.prefix(3500)),
                            chapterText: String(chapterText.prefix(5000)),
                            searchResults: PDFDocumentAgentIndex.evidenceText(evidence),
                            context: context
                        ))
                    }
                }
            }
        }
    }

    private func currentPDFNearbyPagesText() -> String {
        guard let document = pdfView.document,
              let currentIndex = currentPageIndex() else { return "" }
        let lower = max(0, currentIndex - 2)
        let upper = min(document.pageCount - 1, currentIndex + 2)
        let parts = (lower...upper).compactMap { index -> String? in
            guard index != currentIndex,
                  let page = document.page(at: index) else { return nil }
            let text = ReaderAIContextBuilder.pdfPageTranslationText(document: document, page: page, title: titleLabel.stringValue)
            let normalized = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(text)
            guard !normalized.isEmpty else { return nil }
            return "[Page \(index + 1)]\n\(String(normalized.prefix(1200)))"
        }
        return parts.joined(separator: "\n\n")
    }

    private func appendEvidenceBubbles(_ evidence: [PDFDocumentAgentEvidence]) {
        if evidence.isEmpty {
            aiPanel.appendNotice(AppText.localized("未检索到明确文档依据，将主要结合当前问题和阅读上下文回答。", "No strong document evidence was found; the answer will rely mostly on the question and reading context."))
            return
        }
        if let top = evidence.first, top.score < 6 {
            aiPanel.appendNotice(AppText.localized("文档依据较弱，回答会以谨慎判断为主。", "Document evidence is weak; the answer will be cautious."))
        }
        let bubbles = evidence.prefix(4).map { item in
            AIChatPanel.LinkedWordBubble(
                id: "pdf-page:\(item.pageIndex)",
                word: "Page \(item.pageNumber)",
                question: AppText.localized("检索依据 第 \(item.pageNumber) 页", "Source p. \(item.pageNumber)"),
                answer: String(item.text.prefix(500))
            )
        }
        aiPanel.appendReferenceBubbles(bubbles)
    }

    private func documentTitleForAI() -> String {
        var title = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let removableSuffixes = [
            " - PDF Room",
            "- PDF Room",
            " PDF Room",
            "-Chinese-translated",
            "-translated",
            "_Chinese-translated"
        ]
        for suffix in removableSuffixes where title.localizedCaseInsensitiveContains(suffix) {
            title = title.replacingOccurrences(of: suffix, with: "", options: [.caseInsensitive])
        }
        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_").union(.whitespacesAndNewlines))
        return title.isEmpty ? titleLabel.stringValue : title
    }

    private func crossLingualRetrievalQueryIfNeeded(
        question: String,
        currentPageText: String,
        completion: @escaping (String?) -> Void
    ) {
        guard questionLooksMostlyChinese(question),
              textLooksMostlyEnglish(currentPageText),
              AISettingsStore.hasAPIKeyForSelectedModel else {
            completion(nil)
            return
        }

        let prompt = """
        Convert the user's Chinese document-search question into one concise English search query for retrieving passages from an English book.

        Requirements:
        - Output only the English search query.
        - Keep names, places, book-specific terms, and quoted words.
        - Do not answer the question.
        - Do not add explanations.

        Chinese question:
        \(question)
        """
        retrievalQueryClient.send(messages: [
            ChatMessage(role: "system", content: "You create concise English search queries."),
            ChatMessage(role: "user", content: prompt)
        ]) { result in
            if case .success(let text) = result {
                let cleaned = text
                    .replacingOccurrences(of: #"^[\"“”']+|[\"“”']+$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(cleaned.isEmpty ? nil : String(cleaned.prefix(240)))
                return
            }
            completion(nil)
        }
    }

    private func questionLooksMostlyChinese(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        return chineseCount >= 2 && chineseCount * 2 >= max(1, letterCount)
    }

    private func textLooksMostlyEnglish(_ text: String) -> Bool {
        let sample = String(text.prefix(1200))
        let scalars = sample.unicodeScalars
        let latinCount = scalars.filter {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }.count
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        return latinCount >= 80 && latinCount > chineseCount * 4
    }

    private func preparePDFEmbeddingsIfPossible() {
        guard !isPreparingPDFEmbeddings,
              let documentID = currentFileMD5,
              let index = pdfAgentIndex,
              let config = EmbeddingClient.configFromCurrentAISettings(),
              let store = pdfEmbeddingStore else {
            return
        }

        let chunks = index.indexableChunks.map {
            PDFEmbeddingChunk(id: $0.id, pageIndex: $0.pageIndex, chunkIndex: $0.chunkIndex, text: $0.text)
        }
        let cached = store.embeddings(documentID: documentID, model: config.cacheModelID, chunkIDs: chunks.map(\.id))
        pdfAgentIndex?.applyEmbeddings(cached)

        let missing = pdfAgentIndex?.missingEmbeddingChunks(limit: 24).map {
            PDFEmbeddingChunk(id: $0.id, pageIndex: $0.pageIndex, chunkIndex: $0.chunkIndex, text: $0.text)
        } ?? []
        guard !missing.isEmpty else { return }

        aiPanel.appendNotice(AppText.localized("正在增强文档索引：本次处理 \(missing.count) 个片段。", "Enhancing document index: processing \(missing.count) chunks."))
        isPreparingPDFEmbeddings = true
        embeddingClient.embed(texts: missing.map(\.text), config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPreparingPDFEmbeddings = false
                guard case .success(let embeddings) = result else { return }
                store.save(documentID: documentID, model: config.cacheModelID, chunks: missing, embeddings: embeddings)
                let mapped = Dictionary(uniqueKeysWithValues: zip(missing.map(\.id), embeddings))
                self.pdfAgentIndex?.applyEmbeddings(mapped)
            }
        }
    }

    private func queryEmbedding(for question: String, completion: @escaping ([Float]?) -> Void) {
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion(nil)
            return
        }
        embeddingClient.embed(texts: [question], config: config) { result in
            if case .success(let embeddings) = result {
                completion(embeddings.first)
                return
            }
            completion(nil)
        }
    }

    private func currentWebVisibleText(preserveLineBreaks: Bool = false, completion: @escaping (String) -> Void) {
        let script = ReaderAIContextBuilder.visibleWebTextScript(preserveLineBreaks: preserveLineBreaks)
        webView.evaluateJavaScript(script) { value, _ in
            let text = (value as? String) ?? ""
            completion(ReaderAIContextBuilder.normalizeVisibleWebText(text, preserveLineBreaks: preserveLineBreaks))
        }
    }

    private func currentWebProgressTextWindow() -> String {
        ReaderAIContextBuilder.webProgressTextWindow(plainText: currentWebPlainText, progress: webScrollProgress)
    }

    private func currentPDFPageSummaryText() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return "" }
        return ReaderAIContextBuilder.pdfPageSummaryText(document: document, page: page)
    }

    private func currentPDFPageTranslationText() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return "" }
        return ReaderAIContextBuilder.pdfPageTranslationText(
            document: document,
            page: page,
            title: titleLabel.stringValue
        )
    }

    private func shouldPersistHighlight(for text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 80 else { return false }
        let words = normalized.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*(\s+[A-Za-z][A-Za-z'’-]*){0,4}$"#, options: .regularExpression) != nil
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
        } else if obj.object as? NSTextField === pageLabel {
            isEditingPageField = true
            if currentDocumentKind == .pdf, let pageIndex = currentPageIndex() {
                pageLabel.stringValue = "\(pageIndex + 1)"
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = false
            updateZoomLabel()
        } else if obj.object as? NSTextField === pageLabel {
            isEditingPageField = false
            updatePageLabel()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === zoomField, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyZoomFromField()
            return true
        }
        if control === pageLabel, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyPageFromField()
            return true
        }
        return false
    }

    private func updateZoomLabel() {
        if isEditingZoomField { return }
        guard currentDocumentKind == .pdf else {
            zoomField.stringValue = "\(webZoomPercent)%"
            return
        }
        zoomField.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    private func updatePageLabel() {
        if isEditingPageField { return }
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

    private func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        pdfWordRecordStore?.load() ?? []
    }

    private func saveStoredWordRecords() {
        pdfWordRecordStore?.save(storedWordRecords)
    }

    private func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    private func saveStoredWebWordRecords() {
        webWordRecordStore?.save(storedWebWordRecords)
    }

    private func storedWordID(at event: NSEvent) -> String? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)

        if let annotation = page.annotation(at: pointOnPage),
           let id = storedWordID(from: annotation) {
            return id
        }

        return page.annotations
            .first { annotation in
                annotation.bounds.contains(pointOnPage) && storedWordID(from: annotation) != nil
            }
            .flatMap(storedWordID(from:))
    }

    private func storedWordID(from annotation: PDFAnnotation) -> String? {
        guard let contents = annotation.contents,
              contents.hasPrefix("leaf-word:") else {
            return nil
        }
        return String(contents.dropFirst("leaf-word:".count))
    }

    private func jumpToStoredLinkedWord(linkID: String) {
        if linkID.hasPrefix("pdf-page:") {
            let rawPage = String(linkID.dropFirst("pdf-page:".count))
            if let pageIndex = Int(rawPage) {
                jumpToPDFPage(index: pageIndex)
            }
            return
        }
        if storedWebWordRecords.contains(where: { $0.id == linkID }) {
            jumpToStoredWebWord(linkID: linkID)
            return
        }
        jumpToStoredPDFWord(linkID: linkID)
    }

    private func jumpToPDFPage(index: Int) {
        guard let page = pdfView.document?.page(at: index) else { return }
        setAIPanelCollapsed(false, animated: true)
        let bounds = page.bounds(for: pdfView.displayBox)
        pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY)))
        lastPageIndex = index
        updatePageLabel()
        saveSession()
    }

    private func jumpToStoredPDFWord(linkID: String) {
        guard let record = storedWordRecords.first(where: { $0.id == linkID }),
              let page = pdfView.document?.page(at: record.pageIndex) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: record.bounds.cgRect.minX, y: record.bounds.cgRect.maxY + 80)
        )
        pdfView.go(to: destination)
        lastPageIndex = record.pageIndex
        updatePageLabel()
        saveSession()
    }

    private func jumpToStoredWebWord(linkID: String) {
        guard let record = storedWebWordRecords.first(where: { $0.id == linkID }) else { return }
        setAIPanelCollapsed(false, animated: true)
        webView.evaluateJavaScript("window.leafReaderScrollToWord(\(jsStringLiteral(linkID)), \(record.scrollProgress));")
    }

    private func selectStoredLinkedWord(linkID: String) {
        guard storedWordRecords.contains(where: { $0.id == linkID })
                || storedWebWordRecords.contains(where: { $0.id == linkID }) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        aiPanel.scrollToLinkedBubble(id: linkID)
    }

    private func fileMD5(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func restoreWebProgressAfterLoad() {
        guard currentDocumentKind != .pdf,
              let progress = sessionStore.loadWebProgress() else {
            return
        }
        let scrollProgress = progress.scrollProgress
        webScrollProgress = scrollProgress
        pageLabel.stringValue = "\(Int(round(scrollProgress * 100)))%"
        if let percent = progress.zoomPercent {
            webZoomPercent = percent
            zoomField.stringValue = "\(webZoomPercent)%"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.currentDocumentKind != .pdf else { return }
            self.applyWebZoomToPage()
            self.zoomField.stringValue = "\(self.webZoomPercent)%"
            self.webView.evaluateJavaScript("""
            (() => {
              const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
              window.scrollTo(0, height * \(scrollProgress));
            })();
            """)
        }
    }

    private func saveWebProgress() {
        guard !isRestoringSession, currentDocumentKind != .pdf else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWebProgressSave) > 0.5 else { return }
        lastWebProgressSave = now
        sessionStore.saveWebProgress(scrollProgress: webScrollProgress, zoomPercent: webZoomPercent)
    }

    private func restoreBookProgressOrGoHome() {
        guard let document = pdfView.document else { return }
        guard let progress = sessionStore.loadPDFProgress() else {
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
            }
            applyReadablePDFScale()
            return
        }

        let pageIndex = progress.pageIndex
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        } else if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
        }

        let scale = progress.scale
        if scale >= 0.1, scale <= 8 {
            applyReadablePDFScale(scale)
        }
    }

    private func applyReadablePDFScale(_ scale: CGFloat = ReaderWindowController.minimumReadablePDFScale) {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(scale, Self.minimumReadablePDFScale), 8)
        updateZoomLabel()
    }

    private func saveSession() {
        if isRestoringSession { return }
        guard let url = currentFileURL else { return }
        sessionStore.saveLastDocumentURL(url)
        guard currentDocumentKind == .pdf else {
            saveWebProgress()
            return
        }
        let pageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        sessionStore.savePDFProgress(pageIndex: pageIndex, scale: pdfView.scaleFactor)
    }

    private func restoreSession() {
        guard let url = sessionStore.restoreLastDocumentURL() else { return }

        isRestoringSession = true
        loadDocument(url)
        isRestoringSession = false
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    private func installKeyboardPagingMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown]) { [weak self] event in
            guard let self = self, event.window === self.window else { return event }
            switch event.type {
            case .keyDown:
                guard self.handlePageKey(event) else { return event }
                return nil
            case .scrollWheel:
                guard self.handlePDFTrackpadScroll(event) else { return event }
                return nil
            case .leftMouseDown:
                if self.handleStoredWordClick(event) {
                    return nil
                }
                self.clearAISelectionIfClickingReader(event)
                self.hideSearchOverlayIfClickingReader(event)
                return event
            default:
                return event
            }
        }
    }

    private func handleStoredWordClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let linkID = storedWordID(at: event) else {
            return false
        }
        selectStoredLinkedWord(linkID: linkID)
        return true
    }

    private func clearAISelectionIfClickingReader(_ event: NSEvent) {
        guard isMouseEventInsidePDFArea(event) else { return }
        clearAISelectionForNavigation()
    }

    private func hideSearchOverlayIfClickingReader(_ event: NSEvent) {
        guard !searchOverlay.isHidden else { return }

        let pointInContent = contentArea.convert(event.locationInWindow, from: nil)
        guard contentArea.bounds.contains(pointInContent) else { return }

        let pointInSearch = searchOverlay.convert(event.locationInWindow, from: nil)
        guard !searchOverlay.bounds.contains(pointInSearch) else { return }

        hideSearchOverlay()
    }

    private func handlePDFTrackpadScroll(_ event: NSEvent) -> Bool {
        guard currentDocumentKind == .pdf,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              abs(event.scrollingDeltaY) > 0,
              isMouseEventInsidePDFArea(event) else {
            return false
        }

        guard let edgeDirection = pdfTrackpadPageDirectionAtEdge(for: event) else {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            return false
        }

        guard event.momentumPhase == [] else { return true }

        if event.phase == .began {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
        }

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            return true
        }

        guard !didTurnPageForCurrentPDFTrackpadGesture else { return true }

        accumulatedPDFTrackpadScroll += abs(event.scrollingDeltaY)
        let threshold: CGFloat = 95
        guard abs(accumulatedPDFTrackpadScroll) >= threshold else { return true }

        let now = Date()
        guard now.timeIntervalSince(lastPDFTrackpadPageTurn) > 0.45 else {
            accumulatedPDFTrackpadScroll = 0
            return true
        }

        lastPDFTrackpadPageTurn = now
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = true
        turnPageFromScroll(edgeDirection)
        return true
    }

    private func pdfTrackpadPageDirectionAtEdge(for event: NSEvent) -> EdgePagingPDFView.ScrollPageDirection? {
        guard let scrollView = firstScrollView(in: pdfView) else {
            return pdfTrackpadDirection(forDeltaY: event.scrollingDeltaY)
        }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else {
            return pdfTrackpadDirection(forDeltaY: event.scrollingDeltaY)
        }
        let clipHeight = clipView.bounds.height
        let documentHeight = documentView.bounds.height
        guard documentHeight > clipHeight + 2 else {
            return pdfTrackpadDirection(forDeltaY: event.scrollingDeltaY)
        }

        let edgeSlop: CGFloat = 72
        let scrollerValue = scrollView.verticalScroller?.doubleValue
        let isAtTop = clipView.bounds.minY <= edgeSlop || scrollerValue.map { $0 <= 0.02 } == true
        let isAtBottom = clipView.bounds.maxY >= documentHeight - edgeSlop || scrollerValue.map { $0 >= 0.98 } == true

        if isAtTop, event.scrollingDeltaY > 0 {
            return .previous
        }
        if isAtBottom, event.scrollingDeltaY < 0 {
            return .next
        }
        return nil
    }

    private func pdfTrackpadDirection(forDeltaY deltaY: CGFloat) -> EdgePagingPDFView.ScrollPageDirection {
        deltaY > 0 ? .previous : .next
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func isMouseEventInsidePDFArea(_ event: NSEvent) -> Bool {
        let pointInWindow = event.locationInWindow
        let point = pdfContainer.convert(pointInWindow, from: nil)
        return pdfContainer.bounds.contains(point)
    }

    private func handlePageKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            showSearchOverlay()
            return true
        }
        if handleReaderCommandShortcut(event) {
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

    private func handleReaderCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.intersection([.option, .control]).isEmpty,
              !isEditingTextInput,
              !isFirstResponderInsideAIView,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "a":
            selectAllReaderContent()
            return true
        case "c":
            copyReaderSelectionToClipboard()
            return true
        default:
            return false
        }
    }

    private func selectAllReaderContent() {
        if currentDocumentKind == .pdf {
            guard let page = pdfView.currentPage,
                  let selection = page.selection(for: page.bounds(for: pdfView.displayBox)) else {
                return
            }
            pdfView.setCurrentSelection(selection, animate: false)
            selectionChanged()
            return
        }

        webView.evaluateJavaScript("""
        (() => {
          const viewportTop = 0;
          const viewportBottom = window.innerHeight || document.documentElement.clientHeight || 0;
          const viewportLeft = 0;
          const viewportRight = window.innerWidth || document.documentElement.clientWidth || 0;
          const isVisibleRect = (rect) =>
            rect.width > 0 &&
            rect.height > 0 &&
            rect.bottom >= viewportTop &&
            rect.top <= viewportBottom &&
            rect.right >= viewportLeft &&
            rect.left <= viewportRight;
          const isSelectableTextNode = (node) => {
            if (!node.nodeValue || !node.nodeValue.trim()) return false;
            const parent = node.parentElement;
            if (!parent) return false;
            const style = window.getComputedStyle(parent);
            if (style.display === 'none' || style.visibility === 'hidden') return false;
            const range = document.createRange();
            range.selectNodeContents(node);
            const visible = Array.from(range.getClientRects()).some(isVisibleRect);
            range.detach?.();
            return visible;
          };
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => isSelectableTextNode(node)
              ? NodeFilter.FILTER_ACCEPT
              : NodeFilter.FILTER_REJECT
          });
          let first = null;
          let last = null;
          let node;
          while ((node = walker.nextNode())) {
            if (!first) first = node;
            last = node;
          }
          const selection = window.getSelection();
          selection.removeAllRanges();
          if (!first || !last) return "";
          const range = document.createRange();
          range.setStart(first, 0);
          range.setEnd(last, last.nodeValue.length);
          selection.addRange(range);
          return String(selection || "");
        })();
        """) { [weak self] result, _ in
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.currentWebSelectedText = text.count > 1 ? text : ""
            self?.currentWebSelectionContext = text
            self?.aiPanel.setSelectedText(self?.currentWebSelectedText ?? "")
        }
    }

    private func copyReaderSelectionToClipboard() {
        if currentDocumentKind == .pdf {
            copyTextToClipboard(pdfView.currentSelection?.string)
            return
        }

        webView.evaluateJavaScript("String(window.getSelection ? window.getSelection() : '')") { [weak self] result, _ in
            let text = result as? String
            self?.copyTextToClipboard(text)
        }
    }

    private func copyTextToClipboard(_ text: String?) {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var isFirstResponderInsideAIView: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === aiPanel || responder.isDescendant(of: aiPanel)
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
