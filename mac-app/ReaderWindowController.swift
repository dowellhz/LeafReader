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
    private struct VocabularyExportRecord {
        let word: String
        let answer: String
        let location: String
        let context: String
        let createdAt: Date
    }

    private struct PendingPDFWordRecord {
        let id: String
        let word: String
        let pageIndex: Int
        let bounds: StoredPDFWordRect
        let context: String
        let createdAt: Date
    }

    private struct PendingWebWordRecord {
        let id: String
        let word: String
        let context: String
        let scrollProgress: Double
        let createdAt: Date
    }

    private static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    private static let pdfTwoPageModeDefaultsKey = "pdfTwoPageMode"
    private static let fileMD5CacheDefaultsKey = "fileMD5Cache"
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
    private var pageLayoutButton: NSButton!
    private var searchButton: NSButton!
    private var searchUnderlineButton: SearchUnderlineButton!
    private let embeddingStatusLabel = NSTextField(labelWithString: "")
    private var embeddingPauseButton: NSButton!
    private var embeddingCancelButton: NSButton!
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
    private var pdfTOCGeneration = 0
    private var webZoomPercent = 100
    private var webScrollProgress: Double = 0
    private var lastWebProgressSave = Date.distantPast
    private var accumulatedPDFTrackpadScroll: CGFloat = 0
    private var lastPDFTrackpadPageTurn = Date.distantPast
    private var didTurnPageForCurrentPDFTrackpadGesture = false
    private var lastPDFTrackpadEdgeDirection: EdgePagingPDFView.ScrollPageDirection?
    private var lastPageIndex: Int?
    private var searchResults: [PDFSelection] = []
    private var searchResultIndex = 0
    private var lastSearchQuery = ""
    private var pdfAgentIndex: PDFDocumentAgentIndex?
    private var isBuildingDocumentAgentIndex = false
    private var documentAgentIndexGeneration = 0
    private var pendingDocumentAgentIndexCallbacks: [() -> Void] = []
    private var pdfEmbeddingStore = PDFEmbeddingStore()
    private let embeddingClient = EmbeddingClient()
    private let retrievalQueryClient = AIClient()
    private var isPreparingPDFEmbeddings = false
    private var isEmbeddingBackfillPaused = false
    private var embeddingBackfillNeedsRetry = false
    private var queuedEmbeddingPriorityPageIndex: Int?
    private var pendingEmbeddingReadyCallbacks: [() -> Void] = []
    private var embeddingBackfillGeneration = 0
    private var scheduledEmbeddingCacheRestoreWorkItem: DispatchWorkItem?
    private var scheduledEmbeddingWarmupWorkItem: DispatchWorkItem?
    private var lastReaderInteractionAt = Date()
    private var pendingSessionSaveWorkItem: DispatchWorkItem?
    private var suppressSearchSelectionForAIUntil = Date.distantPast
    private var highlightedSelectionKeys = Set<String>()
    private var storedWordRecords: [StoredPDFWordRecord] = []
    private var pendingPDFWordRecords: [String: PendingPDFWordRecord] = [:]
    private var pdfWordRecordStore: PDFWordRecordStore?
    private var storedWebWordRecords: [StoredWebWordRecord] = []
    private var pendingWebWordRecords: [String: PendingWebWordRecord] = [:]
    private var webWordRecordStore: WebWordRecordStore?
    private var currentVocabularyExportRecords: [VocabularyExportRecord] = []
    private var didRegisterSelectionObserver = false
    private var isRestoringSession = false
    private var isEditingZoomField = false
    private var isEditingPageField = false
    private var isAIPanelCollapsed = true
    private var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    private var aiSettingsPanelController: AISettingsPanelController?
    private var recentDocumentsPanelController: RecentDocumentsPanelController?
    private weak var vocabularyPanel: NSWindow?
    private var vocabularyPanelActivationObserver: NSObjectProtocol?
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
        removeVocabularyPanelActivationObserver()
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
        searchUnderlineButton = SearchUnderlineButton(title: "", target: self, action: #selector(showSearchOverlay))
        searchUnderlineButton.toolTip = AppText.localized("搜索文档", "Search document")
        searchUnderlineButton.isDark = ReaderTheme.selected == .dark
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索文档", "Search document")

        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        tocButton = capsuleButton(title: AppText.localized("目录", "TOC"), symbol: "list.bullet", action: #selector(showTableOfContents))
        recentButton = capsuleButton(title: AppText.localized("书架", "Shelf"), symbol: "books.vertical", action: #selector(showRecentDocuments))
        vocabularyButton = capsuleButton(title: AppText.localized("单词本", "Words"), symbol: "text.book.closed", action: #selector(showVocabularyBook))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)
        pageLayoutButton = capsuleButton(title: "", symbol: "rectangle.split.2x1", action: #selector(togglePDFPageLayout))
        pageLayoutButton.toolTip = AppText.localized("切换单页/双页浏览", "Toggle single/two-page view")
        updatePDFPageLayoutButton()
        embeddingPauseButton = capsuleButton(title: AppText.localized("暂停", "Pause"), symbol: "pause.fill", action: #selector(toggleEmbeddingBackfillPaused))
        embeddingPauseButton.toolTip = AppText.localized("暂停/继续生成向量索引", "Pause/resume vector indexing")
        embeddingCancelButton = capsuleButton(title: AppText.localized("取消", "Cancel"), symbol: "xmark", action: #selector(cancelEmbeddingBackfill))
        embeddingCancelButton.toolTip = AppText.localized("取消本次向量索引任务", "Cancel this vector indexing task")

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
        button.font = AppFont.semibold(ofSize: 18)
        return button
    }

    private func capsuleButton(title: String, symbol: String, action: Selector, imageOnRight: Bool = false) -> NSButton {
        let button = CapsuleChromeButton(title: title, target: self, action: action)
        button.identifier = Self.capsuleButtonIdentifier
        button.controlSize = .regular
        button.font = AppFont.semibold(ofSize: 13)
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
                .font: AppFont.semibold(ofSize: 13),
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
        recentButton.title = AppText.localized("书架", "Shelf")
        vocabularyButton.title = AppText.localized("单词本", "Words")
        prevButton.title = AppText.prev
        nextButton.title = AppText.next
        updatePDFPageLayoutButton()
        for button in [coverButton, tocButton, recentButton, vocabularyButton, prevButton, nextButton, pageLayoutButton] {
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
        controller.currentVectorIndexStatus = { [weak self] in
            self?.currentVectorIndexStatusText() ?? AppText.localized("未打开文档", "No document open")
        }
        controller.onStartVectorIndex = { [weak self] in
            self?.startCurrentVectorIndex()
        }
        controller.onToggleVectorIndexPaused = { [weak self] in
            self?.toggleEmbeddingBackfillPaused()
        }
        controller.onCancelVectorIndex = { [weak self] in
            self?.cancelEmbeddingBackfill()
        }
        controller.onClearCurrentVectorIndex = { [weak self] in
            self?.clearCurrentVectorIndex()
        }
        controller.onClearCurrentWordRecords = { [weak self] in
            self?.clearCurrentBookWordRecords()
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
        isBuildingDocumentAgentIndex = false
        documentAgentIndexGeneration += 1
        pendingDocumentAgentIndexCallbacks.removeAll()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        cancelScheduledEmbeddingWarmup()
        currentTOCItems = []
        pdfTOCDestinations = [:]
        schedulePDFTOCBuild(for: url, displayBox: pdfView.displayBox)
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil
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
        pageLayoutButton.isHidden = false
        applyPDFPageLayout(animated: false)

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
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
    }

    private func schedulePDFTOCBuild(for url: URL, displayBox: PDFDisplayBox) {
        pdfTOCGeneration += 1
        let generation = pdfTOCGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let document = PDFDocument(url: url) else { return }
            let toc = ReaderTOCHelper.pdfTOCItems(from: document, displayBox: displayBox)
            DispatchQueue.main.async {
                guard let self,
                      self.pdfTOCGeneration == generation,
                      self.currentFileURL == url else {
                    return
                }
                self.currentTOCItems = toc.items
                self.pdfTOCDestinations = toc.destinations
            }
        }
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
            isBuildingDocumentAgentIndex = false
            documentAgentIndexGeneration += 1
            pendingDocumentAgentIndexCallbacks.removeAll()
            pendingPDFWordRecords.removeAll()
            pendingWebWordRecords.removeAll()
            cancelScheduledEmbeddingWarmup()
            currentWebPlainText = document.plainText
            currentWebSelectedText = ""
            currentWebSelectionContext = ""
            currentTOCItems = document.tocItems
            pdfTOCDestinations = [:]
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
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
            pageLayoutButton.isHidden = true
            pageLabel.stringValue = "0%"
            zoomField.stringValue = "100%"
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
            applyReaderTheme()
            applyWebZoomToPage()
            restoreWebProgressAfterLoad()
            RecentDocumentsStore.record(url: url, kind: kind)
            saveSession()
            scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
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
            onRemoveItem: { path in
                RecentDocumentsStore.remove(path: path)
            },
            onClearVectorCache: { [weak self] path in
                self?.clearVectorCacheForShelfItem(path: path)
            },
            onClearWordRecords: { [weak self] path in
                self?.clearWordRecordsForShelfItem(path: path)
            },
            onClose: { [weak self] in
                self?.recentDocumentsPanelController = nil
            }
        )
    }

    private func clearVectorCacheForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        if currentFileMD5 == documentID {
            embeddingBackfillGeneration += 1
            isPreparingPDFEmbeddings = false
            isEmbeddingBackfillPaused = false
            queuedEmbeddingPriorityPageIndex = nil
            pdfAgentIndex = nil
            documentAgentIndexGeneration += 1
            pendingDocumentAgentIndexCallbacks.removeAll()
            embeddingStatusLabel.stringValue = AppText.localized("向量索引：已清除当前书", "Embedding: current book cleared")
            embeddingStatusLabel.isHidden = false
            updateEmbeddingControlButtons()
        }
    }

    private func clearWordRecordsForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        if currentFileMD5 == documentID {
            clearCurrentBookWordRecords()
            return
        }
        PDFWordRecordStore(fileMD5: documentID).save([])
        WebWordRecordStore(fileMD5: documentID).save([])
    }

    @objc private func showVocabularyBook() {
        let records: [VocabularyExportRecord]
        if currentDocumentKind == .pdf {
            records = storedWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)"),
                        context: pdfWordContext(for: $0),
                        createdAt: $0.createdAt
                    )
                }
        } else {
            records = storedWebWordRecords
                .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    VocabularyExportRecord(
                        word: $0.word,
                        answer: $0.answer,
                        location: AppText.localized("进度 \(Int(($0.scrollProgress * 100).rounded()))%", "\(Int(($0.scrollProgress * 100).rounded()))%"),
                        context: $0.context,
                        createdAt: $0.createdAt
                    )
                }
        }
        let aggregatedRecords = aggregateVocabularyRecords(records)
        guard !aggregatedRecords.isEmpty else {
            NSSound.beep()
            return
        }
        currentVocabularyExportRecords = aggregatedRecords

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = true

        let isDark = ReaderTheme.selected == .dark
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = (isDark ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1) : NSColor.white).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = (isDark ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1) : NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)).cgColor
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)
        root.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = root

        let title = NSTextField(labelWithString: AppText.localized("本书单词本", "Book Vocabulary"))
        title.font = AppFont.semibold(ofSize: 20)
        title.textColor = isDark ? NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1) : NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "text.book.closed.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = NSColor(red: 0.16, green: 0.45, blue: 0.95, alpha: 1)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for record in aggregatedRecords.prefix(120) {
            stack.addArrangedSubview(vocabularyCard(word: record.word, answer: record.answer, location: record.location, isDark: isDark))
        }

        let closeButton = NSButton(title: AppText.close, target: nil, action: nil)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large
        closeButton.font = AppFont.semibold(ofSize: 14)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeVocabularyBook(_:))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = NSButton(title: AppText.localized("导出 MD", "Export MD"), target: self, action: #selector(exportVocabularyMarkdown(_:)))
        exportMarkdownButton.bezelStyle = .rounded
        exportMarkdownButton.controlSize = .large
        exportMarkdownButton.font = AppFont.semibold(ofSize: 14)
        exportMarkdownButton.translatesAutoresizingMaskIntoConstraints = false

        let exportCSVButton = NSButton(title: AppText.localized("导出 Anki CSV", "Export Anki CSV"), target: self, action: #selector(exportVocabularyCSV(_:)))
        exportCSVButton.bezelStyle = .rounded
        exportCSVButton.controlSize = .large
        exportCSVButton.font = AppFont.semibold(ofSize: 14)
        exportCSVButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [icon, title, scrollView, exportMarkdownButton, exportCSVButton, closeButton] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            exportMarkdownButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            exportMarkdownButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            exportMarkdownButton.widthAnchor.constraint(equalToConstant: 104),
            exportMarkdownButton.heightAnchor.constraint(equalToConstant: 36),
            exportCSVButton.leadingAnchor.constraint(equalTo: exportMarkdownButton.trailingAnchor, constant: 10),
            exportCSVButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            exportCSVButton.widthAnchor.constraint(equalToConstant: 132),
            exportCSVButton.heightAnchor.constraint(equalToConstant: 36),

            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            closeButton.widthAnchor.constraint(equalToConstant: 104),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        vocabularyPanel = panel
        installVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.present(panel, attachedTo: window)
    }

    private func aggregateVocabularyRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        var order: [String] = []
        var grouped: [String: [VocabularyExportRecord]] = [:]
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = record.word
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(record)
        }

        return order.compactMap { key in
            guard let group = grouped[key], let first = group.first else { return nil }
            var seenLocations = Set<String>()
            let locations = group.map(\.location).filter { location in
                guard !seenLocations.contains(location) else { return false }
                seenLocations.insert(location)
                return true
            }
            let locationText: String
            if group.count > 1 {
                locationText = AppText.localized(
                    "出现 \(group.count) 次：\(locations.prefix(6).joined(separator: "、"))",
                    "\(group.count) occurrences: \(locations.prefix(6).joined(separator: ", "))"
                )
            } else {
                locationText = first.location
            }
            let context = group
                .map(\.context)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            let answer = group
                .map(\.answer)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? first.answer
            return VocabularyExportRecord(
                word: first.word,
                answer: answer,
                location: locationText,
                context: context,
                createdAt: first.createdAt
            )
        }
    }

    @objc private func closeVocabularyBook(_ sender: NSButton) {
        guard sender.identifier?.rawValue == "closeVocabularyBook",
              let panel = sender.window else { return }
        closeVocabularyPanel(panel)
    }

    private func closeVocabularyPanel(_ panel: NSWindow) {
        removeVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: window)
        vocabularyPanel = nil
    }

    private func installVocabularyPanelActivationObserver() {
        removeVocabularyPanelActivationObserver()
        vocabularyPanelActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let panel = self?.vocabularyPanel else { return }
            ModalOverlayManager.shared.reactivate(panel)
        }
    }

    private func removeVocabularyPanelActivationObserver() {
        if let vocabularyPanelActivationObserver {
            NotificationCenter.default.removeObserver(vocabularyPanelActivationObserver)
            self.vocabularyPanelActivationObserver = nil
        }
    }

    @objc private func exportVocabularyMarkdown(_ sender: NSButton) {
        exportVocabulary(format: .markdown)
    }

    @objc private func exportVocabularyCSV(_ sender: NSButton) {
        exportVocabulary(format: .csv)
    }

    private enum VocabularyExportFormat {
        case markdown
        case csv

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .csv: return "csv"
            }
        }
    }

    private func exportVocabulary(format: VocabularyExportFormat) {
        let records = currentVocabularyExportRecords
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
        guard !records.isEmpty else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = "\(safeExportFileName(documentTitleForAI()))-vocabulary.\(format.fileExtension)"
        savePanel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let output: String
                switch format {
                case .markdown:
                    output = self?.vocabularyMarkdown(records) ?? ""
                case .csv:
                    output = self?.vocabularyCSV(records) ?? ""
                }
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func vocabularyMarkdown(_ records: [VocabularyExportRecord]) -> String {
        var lines: [String] = [
            "# \(documentTitleForAI()) 单词本",
            "",
            "- 导出时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))",
            "- 单词数量：\(records.count)",
            ""
        ]
        for record in records {
            lines.append("## \(record.word)")
            lines.append("")
            lines.append("- 位置：\(record.location)")
            if !record.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("- 原文上下文：\(record.context)")
            }
            lines.append("")
            lines.append(vocabularyAnswerBody(record.answer, word: record.word))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func vocabularyCSV(_ records: [VocabularyExportRecord]) -> String {
        var rows = ["Front,Back,Page,Context,Source,Created At"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([
                record.word,
                vocabularyAnswerBody(record.answer, word: record.word),
                record.location,
                record.context,
                documentTitleForAI(),
                formatter.string(from: record.createdAt)
            ].map(csvEscaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func pdfWordContext(for record: StoredPDFWordRecord) -> String {
        if let context = record.context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            return context
        }
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return "" }
        let pageText = page.string ?? ""
        let selectedText = record.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: pageText, radius: 24) {
            return context
        }
        let expandedBounds = record.bounds.cgRect.insetBy(dx: -120, dy: -36)
        if let nearbyText = page.selection(for: expandedBounds)?.string,
           let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: nearbyText, radius: 24) {
            return context
        }
        return ReaderAIContextBuilder.normalizeWhitespace(page.selection(for: record.bounds.cgRect.insetBy(dx: -80, dy: -24))?.string ?? "")
    }

    private func safeExportFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func vocabularyCard(word: String, answer: String, location: String, isDark: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = (isDark ? NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1) : NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (isDark ? NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1) : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let bullet = NSTextField(labelWithString: "•")
        bullet.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        bullet.textColor = NSColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 1)
        bullet.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: word)
        wordLabel.font = AppFont.semibold(ofSize: 17)
        wordLabel.textColor = isDark ? NSColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1) : NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let locationLabel = NSTextField(labelWithString: location)
        locationLabel.font = AppFont.semibold(ofSize: 12)
        locationLabel.textColor = isDark ? NSColor(red: 0.56, green: 0.63, blue: 0.72, alpha: 1) : NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        locationLabel.alignment = .right
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let answerColor = isDark ? NSColor(red: 0.76, green: 0.80, blue: 0.86, alpha: 1) : NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1)
        let answerBody = vocabularyAnswerBody(answer, word: word)
        let answerLabel = NSTextField(labelWithAttributedString: MarkdownRenderer.render(String(answerBody.prefix(900)), fontSize: 13, textColor: answerColor))
        answerLabel.maximumNumberOfLines = 0
        answerLabel.lineBreakMode = .byWordWrapping
        answerLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [bullet, wordLabel, locationLabel, answerLabel] {
            card.addSubview(view)
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 516),
            bullet.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            bullet.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            wordLabel.leadingAnchor.constraint(equalTo: bullet.trailingAnchor, constant: 8),
            wordLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            locationLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            locationLabel.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: locationLabel.leadingAnchor, constant: -12),
            answerLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 10),
            answerLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            answerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            answerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func vocabularyAnswerBody(_ answer: String, word: String) -> String {
        var lines = answer.components(separatedBy: .newlines)
        let normalizedWord = normalizeVocabularyHeading(word)
        while let first = lines.first {
            let normalizedFirst = normalizeVocabularyHeading(first)
            if normalizedFirst.isEmpty {
                lines.removeFirst()
                continue
            }
            if normalizedFirst == normalizedWord {
                lines.removeFirst()
                continue
            }
            break
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeVocabularyHeading(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\*\*(.*)\*\*$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^__(.*)__$"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
            .lowercased()
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
        markReaderInteraction()
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
        markReaderInteraction()
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
        markReaderInteraction()
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
        markReaderInteraction()
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
        markReaderInteraction()
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

    @objc private func togglePDFPageLayout() {
        guard currentDocumentKind == .pdf else { return }
        let nextValue = !isPDFTwoPageModeEnabled()
        setPDFTwoPageModeEnabled(nextValue)
        applyPDFPageLayout(animated: true)
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    private func applyPDFPageLayout(animated: Bool) {
        guard currentDocumentKind == .pdf else { return }
        let currentPage = pdfView.currentPage
        let currentPageIndex = currentPage.flatMap { pdfView.document?.index(for: $0) }
        let currentDestination = currentPage.map { PDFDestination(page: $0, at: pdfView.convert(pdfView.bounds.origin, to: $0)) }
        let currentScaleFactor = pdfView.scaleFactor
        let isTwoPage = isPDFTwoPageModeEnabled()
        let targetMode: PDFDisplayMode = isTwoPage ? .twoUp : .singlePage
        let needsDisplayModeChange = pdfView.displayMode != targetMode
        let needsBookModeChange = pdfView.displaysAsBook
        guard needsDisplayModeChange || needsBookModeChange else {
            updatePDFPageLayoutButton()
            return
        }
        pageLayoutButton?.isEnabled = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.08 : 0
            pdfView.autoScales = false
            if needsBookModeChange {
                pdfView.displaysAsBook = false
            }
            if needsDisplayModeChange {
                pdfView.displayMode = targetMode
            }
            pdfView.scaleFactor = currentScaleFactor
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let currentPage,
               let currentPageIndex,
               self.pdfView.document?.index(for: self.pdfView.currentPage ?? PDFPage()) != currentPageIndex {
                self.pdfView.go(to: currentPage)
            }
            if let currentDestination {
                self.pdfView.go(to: currentDestination)
            }
            self.pdfView.scaleFactor = currentScaleFactor
            self.pageLayoutButton?.isEnabled = true
            self.updateZoomLabel()
        }
        updatePDFPageLayoutButton()
    }

    private func updatePDFPageLayoutButton() {
        let isTwoPage = isPDFTwoPageModeEnabled()
        pageLayoutButton?.title = isTwoPage
            ? AppText.localized("单页", "Single")
            : AppText.localized("双页", "Two-up")
        pageLayoutButton?.toolTip = isTwoPage
            ? AppText.localized("切换到单页浏览", "Switch to single-page view")
            : AppText.localized("切换到双页浏览", "Switch to two-page view")
    }

    private func isPDFTwoPageModeEnabled() -> Bool {
        let defaults = UserDefaults.standard
        let key = pdfTwoPageModeDefaultsKeyForCurrentBook()
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaults.bool(forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    private func setPDFTwoPageModeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: pdfTwoPageModeDefaultsKeyForCurrentBook())
        defaults.set(enabled, forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    private func pdfTwoPageModeDefaultsKeyForCurrentBook() -> String {
        guard let currentFileMD5, !currentFileMD5.isEmpty else {
            return Self.pdfTwoPageModeDefaultsKey
        }
        return "\(Self.pdfTwoPageModeDefaultsKey).\(currentFileMD5)"
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
        markReaderInteraction()
        let newPageIndex = currentPageIndex()
        guard newPageIndex != lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: newPageIndex)
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
            markReaderInteraction()
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

        let selectionBounds = selection.bounds(for: page)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: selectionBounds,
            queryText: text
        ) ?? selectionBounds.insetBy(dx: -1.5, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            return existing.id
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let record = StoredPDFWordRecord(
                id: UUID().uuidString,
                word: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageIndex: pageIndex,
                bounds: StoredPDFWordRect(bounds),
                context: contextForCurrentSelection(selectedText: text),
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date()
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecords()
            return record.id
        }

        let id = UUID().uuidString
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: contextForCurrentSelection(selectedText: text),
            createdAt: Date()
        )
        return id
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
        if let reusable = reusableWebWordRecord(for: word) {
            let record = StoredWebWordRecord(
                id: UUID().uuidString,
                word: word,
                context: context,
                scrollProgress: webScrollProgress,
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date()
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecords()
            restoreStoredWebWordHighlights()
            return record.id
        }

        let id = UUID().uuidString
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            scrollProgress: webScrollProgress,
            createdAt: Date()
        )
        return id
    }

    private func precisePDFSelectionBounds(page: PDFPage, originalBounds: CGRect, queryText: String) -> CGRect? {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 80,
              let pageText = page.string,
              !pageText.isEmpty else {
            return nil
        }

        let candidates = pdfTextRanges(matching: normalizedQuery, in: pageText)
        guard !candidates.isEmpty else { return nil }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestBounds: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for range in candidates {
            guard let candidateSelection = page.selection(for: range) else { continue }
            let candidateBounds = candidateSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
            guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }

            let intersectsOriginal = originalBounds.insetBy(dx: -8, dy: -6).intersects(candidateBounds)
            let candidateCenter = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
            let distance = hypot(candidateCenter.x - originalCenter.x, candidateCenter.y - originalCenter.y)
            let score = intersectsOriginal ? distance : distance + 10_000
            if score < bestScore {
                bestScore = score
                bestBounds = candidateBounds
            }
        }

        return bestBounds
    }

    private func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        let words = query.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: #"\s+"#)
        let pattern: String
        if words.count == 1 {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        } else {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)).map(\.range)
    }

    private func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            pendingPDFWordRecords.removeValue(forKey: linkID)
            pendingWebWordRecords.removeValue(forKey: linkID)
            return
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWordRecords[index].question = question
            storedWordRecords[index].answer = trimmedAnswer
            saveStoredWordRecords()
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWebWordRecords[index].question = question
            storedWebWordRecords[index].answer = trimmedAnswer
            saveStoredWebWordRecords()
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                word: pending.word,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecords()
            return
        }

        if let pending = pendingWebWordRecords.removeValue(forKey: linkID) {
            let record = StoredWebWordRecord(
                id: pending.id,
                word: pending.word,
                context: pending.context,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecords()
            restoreStoredWebWordHighlights()
        }
    }

    private func discardPendingLinkedWord(linkID: String) {
        pendingPDFWordRecords.removeValue(forKey: linkID)
        pendingWebWordRecords.removeValue(forKey: linkID)
    }

    private func linkedWordAnswer(for linkID: String) -> String? {
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        return nil
    }

    private func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWebWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private func clearCurrentBookWordRecords() {
        if currentDocumentKind == .pdf {
            clearCurrentPDFWordRecords()
        } else {
            clearCurrentWebWordRecords()
        }
        aiPanel.loadLinkedWordBubbles([])
    }

    private func clearCurrentPDFWordRecords() {
        guard !storedWordRecords.isEmpty else { return }
        for record in storedWordRecords {
            guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
            for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                page.removeAnnotation(annotation)
            }
        }
        storedWordRecords.removeAll()
        highlightedSelectionKeys.removeAll()
        saveStoredWordRecords()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func clearCurrentWebWordRecords() {
        guard !storedWebWordRecords.isEmpty else { return }
        storedWebWordRecords.removeAll()
        saveStoredWebWordRecords()
        let script = """
        (() => {
          document.querySelectorAll('span.leaf-reader-linked-word').forEach((span) => {
            const parent = span.parentNode;
            if (!parent) return;
            while (span.firstChild) parent.insertBefore(span.firstChild, span);
            parent.removeChild(span);
            parent.normalize();
          });
        })();
        """
        webView.evaluateJavaScript(script)
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
        currentReadingContextSnapshot(preserveLineBreaks: false) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeWhitespace(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(6000))))
        }
    }

    private func currentTranslationContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(9000))))
        }
    }

    private func currentReadingQuestionContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(5000))))
        }
    }

    private func currentReadingContextSnapshot(
        preserveLineBreaks: Bool,
        completion: @escaping (ReadingContextSnapshot?) -> Void
    ) {
        let title = documentTitleForAI()
        if currentDocumentKind == .pdf {
            let visibleText = preserveLineBreaks
                ? ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFPageTranslationText())
                : ReaderAIContextBuilder.normalizeWhitespace(currentPDFPageSummaryText())
            let nearbyText = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFNearbyPagesText())
            let selectedText = (pdfView.currentSelection?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedContext = selectedText.isEmpty ? "" : contextForCurrentSelection(selectedText: selectedText)
            completion(ReadingContextSnapshot(
                title: title,
                documentKind: .pdf,
                locationLabel: currentPDFLocationLabel(),
                visibleText: visibleText,
                nearbyText: nearbyText,
                selectedText: selectedText,
                selectedContext: selectedContext
            ))
            return
        }

        currentWebVisibleText(preserveLineBreaks: preserveLineBreaks) { [weak self] visibleText in
            guard let self else {
                completion(nil)
                return
            }
            let nearbyText = preserveLineBreaks
                ? ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(self.currentWebProgressTextWindow())
                : ReaderAIContextBuilder.normalizeWhitespace(self.currentWebProgressTextWindow())
            let selectedText = self.currentWebSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedContext = selectedText.isEmpty ? "" : self.contextForCurrentSelection(selectedText: selectedText)
            completion(ReadingContextSnapshot(
                title: title,
                documentKind: self.currentDocumentKind,
                locationLabel: self.currentWebLocationLabel(),
                visibleText: visibleText,
                nearbyText: nearbyText,
                selectedText: selectedText,
                selectedContext: selectedContext
            ))
        }
    }

    private func currentPDFLocationLabel() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else {
            return ""
        }
        let index = document.index(for: page)
        return AppText.localized("第 \(index + 1) / \(document.pageCount) 页", "Page \(index + 1) / \(document.pageCount)")
    }

    private func currentWebLocationLabel() -> String {
        let percent = min(100, max(0, Int(round(webScrollProgress * 100))))
        let kind = currentDocumentKind == .epub ? "EPUB" : "DOCX"
        return AppText.localized("\(kind) 约 \(percent)% 位置", "\(kind) about \(percent)%")
    }

    private func documentAgentPrompt(question: String, context: String, completion: @escaping (String?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, let snapshot else {
                    completion(nil)
                    return
                }
                if self.currentDocumentKind == .pdf {
                    self.pdfDocumentAgentPrompt(question: question, context: context, snapshot: snapshot, completion: completion)
                    return
                }
                self.webDocumentAgentPrompt(question: question, context: context, snapshot: snapshot, completion: completion)
            }
        }
    }

    private func pdfDocumentAgentPrompt(
        question: String,
        context: String,
        snapshot: ReadingContextSnapshot,
        completion: @escaping (String?) -> Void
    ) {
        guard pdfView.document != nil else {
            completion(nil)
            return
        }

        let currentPageText = snapshot.visibleText
        let chapterText = snapshot.nearbyText
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: currentPageText) { [weak self] retrievalQuery in
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
                    let currentPageIndex = self.currentPageIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: currentPageIndex) { [weak self] in
                        guard let self else {
                            completion(nil)
                            return
                        }
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
                                var searchResults = PDFDocumentAgentIndex.evidenceText(evidence, locationName: self.evidenceLocationName())
                                if let coverageText = self.embeddingCoveragePromptText() {
                                    searchResults = searchResults.isEmpty ? coverageText : "\(coverageText)\n\n\(searchResults)"
                                }
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: self.documentTitleForAI(),
                                    question: question,
                                    currentPageText: String(currentPageText.prefix(3500)),
                                    chapterText: String(chapterText.prefix(5000)),
                                    searchResults: searchResults,
                                    context: combinedContext
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    private func webDocumentAgentPrompt(
        question: String,
        context: String,
        snapshot: ReadingContextSnapshot,
        completion: @escaping (String?) -> Void
    ) {
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: snapshot.visibleText) { [weak self] retrievalQuery in
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
                    let priorityIndex = self.currentEmbeddingPriorityIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: priorityIndex) { [weak self] in
                        guard let self else {
                            completion(nil)
                            return
                        }
                        self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                            DispatchQueue.main.async {
                                guard let self else {
                                    completion(nil)
                                    return
                                }
                                let evidence = self.pdfAgentIndex?.search(
                                    question: retrievalQuestion,
                                    currentPageIndex: self.currentEmbeddingPriorityIndex(),
                                    queryEmbedding: queryEmbedding
                                ) ?? []
                                self.appendEvidenceBubbles(evidence)
                                var searchResults = PDFDocumentAgentIndex.evidenceText(evidence, locationName: self.evidenceLocationName())
                                if let coverageText = self.embeddingCoveragePromptText() {
                                    searchResults = searchResults.isEmpty ? coverageText : "\(coverageText)\n\n\(searchResults)"
                                }
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: snapshot.title,
                                    question: question,
                                    currentPageText: String(snapshot.visibleText.prefix(3500)),
                                    chapterText: String(snapshot.nearbyText.prefix(5000)),
                                    searchResults: searchResults,
                                    context: combinedContext,
                                    currentTextTitle: AppText.localized("当前可见内容", "Current visible text"),
                                    nearbyTextTitle: AppText.localized("当前阅读位置附近内容", "Nearby reading text")
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    private func combinedReadingContext(base: String, snapshot: ReadingContextSnapshot) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty, trimmedBase != AppText.none {
            parts.append(trimmedBase)
        }
        let snapshotContext = snapshot.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snapshotContext.isEmpty {
            parts.append(snapshotContext)
        }
        return String(parts.joined(separator: "\n\n").suffix(6000))
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
            let label = currentDocumentKind == .pdf
                ? AppText.localized("第 \(item.pageNumber) 页", "Page \(item.pageNumber)")
                : AppText.localized("片段 \(item.pageNumber)", "Section \(item.pageNumber)")
            return AIChatPanel.LinkedWordBubble(
                id: "document-source:\(item.pageIndex)",
                word: label,
                question: AppText.localized("检索依据 \(label)", "Source \(label)"),
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

    private func ensureDocumentAgentIndex() {
        guard pdfAgentIndex == nil else { return }
        if currentDocumentKind == .pdf {
            guard let document = pdfView.document else { return }
            pdfAgentIndex = PDFDocumentAgentIndex(document: document, title: titleLabel.stringValue)
            return
        }
        guard !currentWebPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pdfAgentIndex = PDFDocumentAgentIndex(text: currentWebPlainText)
    }

    private func ensureDocumentAgentIndexAsync(completion: (() -> Void)? = nil) {
        if pdfAgentIndex != nil {
            completion?()
            return
        }
        if let completion {
            pendingDocumentAgentIndexCallbacks.append(completion)
        }
        guard !isBuildingDocumentAgentIndex else { return }

        isBuildingDocumentAgentIndex = true
        let generation = documentAgentIndexGeneration
        let kind = currentDocumentKind
        let title = titleLabel.stringValue

        if kind == .pdf {
            guard let url = currentFileURL else {
                finishDocumentAgentIndexBuild(nil, generation: generation)
                return
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                autoreleasepool {
                    let document = PDFDocument(url: url)
                    let index = document.map { PDFDocumentAgentIndex(document: $0, title: title) }
                    DispatchQueue.main.async {
                        self?.finishDocumentAgentIndexBuild(index, generation: generation)
                    }
                }
            }
            return
        }

        let text = currentWebPlainText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishDocumentAgentIndexBuild(nil, generation: generation)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let index = PDFDocumentAgentIndex(text: text)
            DispatchQueue.main.async {
                self?.finishDocumentAgentIndexBuild(index, generation: generation)
            }
        }
    }

    private func finishDocumentAgentIndexBuild(_ index: PDFDocumentAgentIndex?, generation: Int) {
        guard generation == documentAgentIndexGeneration else { return }
        pdfAgentIndex = index
        isBuildingDocumentAgentIndex = false
        let callbacks = pendingDocumentAgentIndexCallbacks
        pendingDocumentAgentIndexCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    private func currentEmbeddingPriorityIndex() -> Int? {
        if currentDocumentKind == .pdf {
            return currentPageIndex()
        }
        guard let count = pdfAgentIndex?.locationCount, count > 0 else { return nil }
        let index = Int((Double(count - 1) * min(1, max(0, webScrollProgress))).rounded())
        return min(count - 1, max(0, index))
    }

    private func evidenceLocationName() -> String {
        currentDocumentKind == .pdf ? "Page" : AppText.localized("片段", "Section")
    }

    private func scheduleDocumentEmbeddingWarmup(priorityPageIndex: Int?) {
        guard AISettingsStore.autoEmbeddingIndexEnabled,
              EmbeddingClient.configFromCurrentAISettings() != nil else {
            return
        }
        let documentID = currentFileMD5
        scheduledEmbeddingCacheRestoreWorkItem?.cancel()
        let cacheWorkItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            guard self.currentFileMD5 == documentID,
                  self.window?.isVisible == true else {
                return
            }
            self.ensureDocumentAgentIndexAsync { [weak self] in
                guard let self, self.currentFileMD5 == documentID else { return }
                self.applyCachedEmbeddingsIfPossible()
                if self.embeddingIndexIsComplete {
                    self.scheduledEmbeddingWarmupWorkItem?.cancel()
                    self.scheduledEmbeddingWarmupWorkItem = nil
                }
            }
        }
        scheduledEmbeddingCacheRestoreWorkItem = cacheWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: cacheWorkItem)

        scheduledEmbeddingWarmupWorkItem?.cancel()
        let warmupWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentFileMD5 == documentID else { return }
            guard self.window?.isVisible == true else {
                return
            }
            guard self.isReaderIdleForEmbedding else {
                self.embeddingStatusLabel.stringValue = AppText.localized("向量索引：空闲后继续", "Embedding: continues when idle")
                self.embeddingStatusLabel.isHidden = false
                self.scheduleDocumentEmbeddingWarmup(priorityPageIndex: priorityPageIndex)
                return
            }
            self.ensureDocumentAgentIndexAsync { [weak self] in
                guard let self, self.currentFileMD5 == documentID else { return }
                self.applyCachedEmbeddingsIfPossible()
                guard !self.embeddingIndexIsComplete else {
                    self.scheduledEmbeddingWarmupWorkItem = nil
                    return
                }
                self.preparePDFEmbeddingsIfPossible(priorityPageIndex: priorityPageIndex)
            }
        }
        scheduledEmbeddingWarmupWorkItem = warmupWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 18.0, execute: warmupWorkItem)
    }

    private var isReaderIdleForEmbedding: Bool {
        Date().timeIntervalSince(lastReaderInteractionAt) >= 4.0
    }

    private func markReaderInteraction() {
        lastReaderInteractionAt = Date()
    }

    private func cancelScheduledEmbeddingWarmup() {
        scheduledEmbeddingCacheRestoreWorkItem?.cancel()
        scheduledEmbeddingCacheRestoreWorkItem = nil
        scheduledEmbeddingWarmupWorkItem?.cancel()
        scheduledEmbeddingWarmupWorkItem = nil
    }

    private func applyCachedEmbeddingsIfPossible() {
        guard let documentID = currentFileMD5,
              let index = pdfAgentIndex,
              let config = EmbeddingClient.configFromCurrentAISettings(),
              let store = pdfEmbeddingStore else {
            return
        }
        let chunks = index.indexableChunks
        guard !chunks.isEmpty else { return }
        let cached = store.embeddings(documentID: documentID, model: config.cacheModelID, chunkIDs: chunks.map(\.id))
        pdfAgentIndex?.applyEmbeddings(cached)
        if !cached.isEmpty {
            updateEmbeddingStatusForCoverage(isComplete: index.embeddingCoverage.embedded >= index.embeddingCoverage.total)
        }
    }

    private var embeddingIndexIsComplete: Bool {
        guard let progress = pdfAgentIndex?.embeddingCoverage,
              progress.total > 0 else {
            return false
        }
        return progress.embedded >= progress.total
    }

    private func preparePDFEmbeddingsIfPossible(priorityPageIndex: Int? = nil, completion: (() -> Void)? = nil) {
        guard let documentID = currentFileMD5,
              pdfAgentIndex != nil,
              let config = EmbeddingClient.configFromCurrentAISettings(),
              let store = pdfEmbeddingStore else {
            completion?()
            return
        }

        if isPreparingPDFEmbeddings {
            if isEmbeddingBackfillPaused {
                isEmbeddingBackfillPaused = false
                updateEmbeddingControlButtons()
                if let documentID = currentFileMD5,
                   let config = EmbeddingClient.configFromCurrentAISettings(),
                   let store = pdfEmbeddingStore {
                    let generation = embeddingBackfillGeneration
                    DispatchQueue.main.async { [weak self] in
                        guard let self, generation == self.embeddingBackfillGeneration else { return }
                        self.continuePDFEmbeddingBackfill(
                            documentID: documentID,
                            config: config,
                            store: store,
                            priorityPageIndex: priorityPageIndex,
                            afterFirstBatch: nil,
                            notifyPendingAfterBatch: true,
                            generation: generation
                        )
                    }
                }
            }
            if let priorityPageIndex {
                queuedEmbeddingPriorityPageIndex = priorityPageIndex
            }
            if let completion {
                pendingEmbeddingReadyCallbacks.append(completion)
            }
            return
        }

        applyCachedEmbeddingsIfPossible()
        if embeddingIndexIsComplete {
            completion?()
            notifyEmbeddingReady(completion, includePending: true)
            updateEmbeddingStatusForCoverage(isComplete: true)
            return
        }

        isPreparingPDFEmbeddings = true
        isEmbeddingBackfillPaused = false
        embeddingBackfillNeedsRetry = false
        embeddingBackfillGeneration += 1
        let generation = embeddingBackfillGeneration
        updateEmbeddingControlButtons()
        continuePDFEmbeddingBackfill(
            documentID: documentID,
            config: config,
            store: store,
            priorityPageIndex: priorityPageIndex,
            afterFirstBatch: completion,
            notifyPendingAfterBatch: completion != nil,
            generation: generation
        )
    }

    private func continuePDFEmbeddingBackfill(
        documentID: String,
        config: EmbeddingModelConfig,
        store: PDFEmbeddingStore,
        priorityPageIndex: Int?,
        afterFirstBatch: (() -> Void)?,
        notifyPendingAfterBatch: Bool,
        generation: Int
    ) {
        guard generation == embeddingBackfillGeneration,
              currentFileMD5 == documentID,
              let index = pdfAgentIndex else {
            isPreparingPDFEmbeddings = false
            queuedEmbeddingPriorityPageIndex = nil
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            clearEmbeddingStatus()
            return
        }
        guard !isEmbeddingBackfillPaused else {
            embeddingStatusLabel.stringValue = AppText.localized("向量索引：已暂停，点击继续", "Embedding: paused, tap resume")
            embeddingStatusLabel.isHidden = false
            updateEmbeddingControlButtons()
            return
        }

        let missing = index.missingEmbeddingChunks(limit: 24, preferredPageIndex: priorityPageIndex).map {
            PDFEmbeddingChunk(id: $0.id, pageIndex: $0.pageIndex, chunkIndex: $0.chunkIndex, text: $0.text)
        }
        guard !missing.isEmpty else {
            isPreparingPDFEmbeddings = false
            isEmbeddingBackfillPaused = false
            queuedEmbeddingPriorityPageIndex = nil
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            updateEmbeddingStatusForCoverage(isComplete: true)
            updateEmbeddingControlButtons()
            return
        }

        updateEmbeddingStatus(chunks: missing)
        embeddingClient.embed(texts: missing.map(\.text), config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.embeddingBackfillGeneration,
                      self.currentFileMD5 == documentID else {
                    self.isPreparingPDFEmbeddings = false
                    self.isEmbeddingBackfillPaused = false
                    self.queuedEmbeddingPriorityPageIndex = nil
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                    self.clearEmbeddingStatus()
                    self.updateEmbeddingControlButtons()
                    return
                }

                switch result {
                case .success(let embeddings):
                    store.save(documentID: documentID, model: config.cacheModelID, chunks: missing, embeddings: embeddings)
                    let mapped = Dictionary(uniqueKeysWithValues: zip(missing.map(\.id), embeddings))
                    self.pdfAgentIndex?.applyEmbeddings(mapped)
                    let nextPriorityPageIndex = self.queuedEmbeddingPriorityPageIndex
                    self.queuedEmbeddingPriorityPageIndex = nil
                    let shouldDeferPendingCallbacks = nextPriorityPageIndex != nil && !self.pendingEmbeddingReadyCallbacks.isEmpty
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: notifyPendingAfterBatch && !shouldDeferPendingCallbacks)
                    self.updateEmbeddingStatusForCoverage(isComplete: false)
                    let shouldNotifyPendingAfterNextBatch = shouldDeferPendingCallbacks
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.continuePDFEmbeddingBackfill(
                            documentID: documentID,
                            config: config,
                            store: store,
                            priorityPageIndex: nextPriorityPageIndex,
                            afterFirstBatch: nil,
                            notifyPendingAfterBatch: shouldNotifyPendingAfterNextBatch,
                            generation: generation
                        )
                    }
                case .failure:
                    self.isPreparingPDFEmbeddings = false
                    self.isEmbeddingBackfillPaused = false
                    self.embeddingBackfillNeedsRetry = true
                    self.queuedEmbeddingPriorityPageIndex = nil
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                    self.embeddingStatusLabel.stringValue = AppText.localized("向量索引：失败，可重试", "Embedding: failed, retry available")
                    self.embeddingStatusLabel.isHidden = false
                    self.updateEmbeddingControlButtons()
                }
            }
        }
    }

    @objc private func toggleEmbeddingBackfillPaused() {
        guard isPreparingPDFEmbeddings else { return }
        isEmbeddingBackfillPaused.toggle()
        updateEmbeddingControlButtons()
        if isEmbeddingBackfillPaused {
            embeddingStatusLabel.stringValue = AppText.localized("向量索引：已暂停，点击继续", "Embedding: paused, tap resume")
            embeddingStatusLabel.isHidden = false
            return
        }
        guard let documentID = currentFileMD5,
              let config = EmbeddingClient.configFromCurrentAISettings(),
              let store = pdfEmbeddingStore else { return }
        continuePDFEmbeddingBackfill(
            documentID: documentID,
            config: config,
            store: store,
            priorityPageIndex: queuedEmbeddingPriorityPageIndex,
            afterFirstBatch: nil,
            notifyPendingAfterBatch: true,
            generation: embeddingBackfillGeneration
        )
    }

    @objc private func cancelEmbeddingBackfill() {
        guard isPreparingPDFEmbeddings else { return }
        embeddingBackfillGeneration += 1
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        queuedEmbeddingPriorityPageIndex = nil
        notifyEmbeddingReady(nil, includePending: true)
        embeddingStatusLabel.stringValue = AppText.localized("向量索引：已取消", "Embedding: cancelled")
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isPreparingPDFEmbeddings else { return }
            self.clearEmbeddingStatus()
        }
    }

    private func startCurrentVectorIndex() {
        guard EmbeddingClient.configFromCurrentAISettings() != nil else {
            embeddingStatusLabel.stringValue = AppText.localized("向量索引：请先配置向量模型", "Embedding: configure model first")
            embeddingStatusLabel.isHidden = false
            return
        }
        embeddingBackfillNeedsRetry = false
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else { return }
            self.preparePDFEmbeddingsIfPossible(priorityPageIndex: self.currentEmbeddingPriorityIndex())
        }
    }

    private func clearCurrentVectorIndex() {
        guard let documentID = currentFileMD5 else {
            NSSound.beep()
            return
        }
        embeddingBackfillGeneration += 1
        isPreparingPDFEmbeddings = false
        isEmbeddingBackfillPaused = false
        queuedEmbeddingPriorityPageIndex = nil
        pendingEmbeddingReadyCallbacks.removeAll()
        pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        pdfAgentIndex = nil
        documentAgentIndexGeneration += 1
        isBuildingDocumentAgentIndex = false
        pendingDocumentAgentIndexCallbacks.removeAll()
        ensureDocumentAgentIndexAsync()
        embeddingStatusLabel.stringValue = AppText.localized("向量索引：已清除当前书", "Embedding: current book cleared")
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isPreparingPDFEmbeddings else { return }
            self.clearEmbeddingStatus()
        }
    }

    private func currentVectorIndexStatusText() -> String {
        guard currentFileMD5 != nil else {
            return AppText.localized("未打开文档。", "No document open.")
        }
        let progress = pdfAgentIndex?.embeddingCoverage ?? (embedded: 0, total: 0)
        let cacheSize = pdfEmbeddingStore?.cacheSizeBytes() ?? 0
        let cacheText = formatEmbeddingBytes(cacheSize)
        guard EmbeddingClient.configFromCurrentAISettings() != nil else {
            return AppText.localized("未配置向量模型。当前缓存占用 \(cacheText)。", "Embedding model is not configured. Cache uses \(cacheText).")
        }
        guard progress.total > 0 else {
            return AppText.localized("当前文档没有可索引文本。当前缓存占用 \(cacheText)。", "This document has no indexable text. Cache uses \(cacheText).")
        }
        let percent = embeddingCoveragePercent(progress)
        let state: String
        if isPreparingPDFEmbeddings {
            state = isEmbeddingBackfillPaused
                ? AppText.localized("已暂停", "paused")
                : AppText.localized("生成中", "indexing")
        } else if embeddingBackfillNeedsRetry {
            state = AppText.localized("失败，可重试", "failed, retry available")
        } else if progress.embedded >= progress.total {
            state = AppText.localized("已缓存", "cached")
        } else if scheduledEmbeddingWarmupWorkItem != nil {
            state = AppText.localized("空闲后继续", "continues when idle")
        } else if progress.embedded > 0 {
            state = AppText.localized("已缓存部分内容", "partially cached")
        } else {
            state = AppText.localized("未生成", "not built")
        }
        return AppText.localized(
            "\(state)：\(percent)%（\(progress.embedded)/\(progress.total) 个片段）。当前缓存占用 \(cacheText)。",
            "\(state): \(percent)% (\(progress.embedded)/\(progress.total) chunks). Cache uses \(cacheText)."
        )
    }

    private func formatEmbeddingBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    private func notifyEmbeddingReady(_ callback: (() -> Void)?, includePending: Bool) {
        callback?()
        guard includePending else { return }
        let callbacks = pendingEmbeddingReadyCallbacks
        pendingEmbeddingReadyCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    private func updateEmbeddingStatus(chunks: [PDFEmbeddingChunk]) {
        let pages = Set(chunks.map(\.pageIndex)).sorted()
        guard let firstPage = pages.first else {
            clearEmbeddingStatus()
            return
        }
        let progress = pdfAgentIndex?.embeddingCoverage ?? (0, 0)
        let percent = embeddingCoveragePercent(progress)
        let text: String
        let unit = currentDocumentKind == .pdf ? AppText.localized("第", "page ") : AppText.localized("片段 ", "section ")
        let suffix = currentDocumentKind == .pdf ? AppText.localized(" 页", "") : ""
        if let lastPage = pages.last, lastPage != firstPage {
            text = AppText.localized(
                "向量索引：生成中 \(percent)% \(unit)\(firstPage + 1)-\(lastPage + 1)\(suffix)",
                "Embedding: indexing \(percent)% \(unit)\(firstPage + 1)-\(lastPage + 1)"
            )
        } else {
            text = AppText.localized(
                "向量索引：生成中 \(percent)% \(unit)\(firstPage + 1)\(suffix)",
                "Embedding: indexing \(percent)% \(unit)\(firstPage + 1)"
            )
        }
        embeddingStatusLabel.stringValue = text
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
    }

    private func updateEmbeddingStatusForCoverage(isComplete: Bool) {
        guard let progress = pdfAgentIndex?.embeddingCoverage, progress.total > 0 else {
            clearEmbeddingStatus()
            return
        }
        let percent = embeddingCoveragePercent(progress)
        let text = isComplete || percent >= 100
            ? AppText.localized("向量索引：已缓存", "Embedding: cached")
            : AppText.localized("向量索引：已缓存 \(percent)%，空闲后继续", "Embedding: cached \(percent)%, continues when idle")
        embeddingStatusLabel.stringValue = text
        embeddingStatusLabel.isHidden = false
        updateEmbeddingControlButtons()
    }

    private func embeddingCoveragePercent(_ progress: (embedded: Int, total: Int)) -> Int {
        guard progress.total > 0 else { return 0 }
        return min(100, Int((Double(progress.embedded) / Double(progress.total) * 100).rounded()))
    }

    private func embeddingCoveragePromptText() -> String? {
        guard let progress = pdfAgentIndex?.embeddingCoverage,
              progress.total > 0,
              progress.embedded < progress.total else {
            return nil
        }
        let percent = embeddingCoveragePercent(progress)
        return AppText.localized(
            "向量索引仍在后台生成，目前覆盖 \(percent)%（\(progress.embedded)/\(progress.total) 个片段）。文档检索结果可能不完整；请先结合当前页内容、附近页面和已检索到的片段回答。",
            "The vector index is still being generated in the background and currently covers \(percent)% (\(progress.embedded)/\(progress.total) chunks). Document retrieval may be incomplete; answer using the current page, nearby pages, and retrieved chunks first."
        )
    }

    private func clearEmbeddingStatus() {
        embeddingStatusLabel.stringValue = ""
        embeddingStatusLabel.isHidden = true
        updateEmbeddingControlButtons()
    }

    private func updateEmbeddingControlButtons() {
        let showControls = isPreparingPDFEmbeddings
        embeddingPauseButton?.isHidden = !showControls
        embeddingCancelButton?.isHidden = !showControls
        embeddingPauseButton?.title = isEmbeddingBackfillPaused
            ? AppText.localized("继续", "Resume")
            : AppText.localized("暂停", "Pause")
        embeddingPauseButton?.toolTip = isEmbeddingBackfillPaused
            ? AppText.localized("继续生成向量索引", "Resume vector indexing")
            : AppText.localized("暂停生成向量索引", "Pause vector indexing")
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
        DispatchQueue.main.async { [weak self] in
            self?.updateZoomLabel()
            self?.saveSession()
        }
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
        if linkID.hasPrefix("document-source:") {
            let rawIndex = String(linkID.dropFirst("document-source:".count))
            if let index = Int(rawIndex) {
                jumpToDocumentSource(index: index)
            }
            return
        }
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

    private func jumpToDocumentSource(index: Int) {
        setAIPanelCollapsed(false, animated: true)
        if currentDocumentKind == .pdf {
            jumpToPDFPage(index: index)
            return
        }
        jumpToWebDocumentSection(index: index)
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

    private func jumpToWebDocumentSection(index: Int) {
        ensureDocumentAgentIndex()
        let count = max(1, pdfAgentIndex?.locationCount ?? 1)
        let progress = count <= 1 ? 0 : Double(min(max(index, 0), count - 1)) / Double(count - 1)
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
        let script = """
        (() => {
          const progress = \(progress);
          const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          window.scrollTo({ top: scrollHeight * progress, behavior: 'smooth' });
        })();
        """
        webView.evaluateJavaScript(script)
        saveWebProgress()
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
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.standardizedFileURL.path)|\(fileSize)|\(modifiedAt)"
        let defaults = UserDefaults.standard
        var cache = defaults.dictionary(forKey: Self.fileMD5CacheDefaultsKey) as? [String: String] ?? [:]
        if let cached = cache[cacheKey] {
            return cached
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        let md5 = digest.map { String(format: "%02x", $0) }.joined()
        cache[cacheKey] = md5
        if cache.count > 80 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(80))
        }
        defaults.set(cache, forKey: Self.fileMD5CacheDefaultsKey)
        return md5
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
        pendingSessionSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSessionSave()
        }
        pendingSessionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func performSessionSave() {
        pendingSessionSaveWorkItem = nil
        guard let url = currentFileURL else { return }
        sessionStore.saveLastDocumentURL(url)
        guard currentDocumentKind == .pdf else {
            saveWebProgress()
            RecentDocumentsStore.updateProgress(url: url, kind: currentDocumentKind, progress: webScrollProgress)
            return
        }
        let pageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        sessionStore.savePDFProgress(pageIndex: pageIndex, scale: pdfView.scaleFactor)
        let pageCount = max(1, pdfView.document?.pageCount ?? 1)
        RecentDocumentsStore.updateProgress(
            url: url,
            kind: currentDocumentKind,
            progress: Double(pageIndex + 1) / Double(pageCount)
        )
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

    private func scheduleSessionRestoreAfterInitialPaint() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.currentFileURL == nil else { return }
            self.restoreSession()
        }
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
                self.markReaderInteraction()
                DispatchQueue.main.async { [weak self] in
                    self?.updateZoomLabel()
                }
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
            lastPDFTrackpadEdgeDirection = nil
            return false
        }

        guard event.momentumPhase == [] else { return true }

        if event.phase == .began {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
        }

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
            return true
        }

        guard !didTurnPageForCurrentPDFTrackpadGesture else { return true }

        if let lastDirection = lastPDFTrackpadEdgeDirection, lastDirection != edgeDirection {
            accumulatedPDFTrackpadScroll = 0
        }
        lastPDFTrackpadEdgeDirection = edgeDirection

        accumulatedPDFTrackpadScroll += abs(event.scrollingDeltaY)
        let threshold = pdfTrackpadPageTurnThreshold()
        guard abs(accumulatedPDFTrackpadScroll) >= threshold else { return true }

        let now = Date()
        guard now.timeIntervalSince(lastPDFTrackpadPageTurn) > 0.8 else {
            accumulatedPDFTrackpadScroll = 0
            return true
        }

        lastPDFTrackpadPageTurn = now
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = true
        lastPDFTrackpadEdgeDirection = nil
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

        let edgeSlop: CGFloat = 22
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

    private func pdfTrackpadPageTurnThreshold() -> CGFloat {
        guard let scrollView = firstScrollView(in: pdfView),
              let documentView = scrollView.documentView else {
            return 220
        }
        let clipHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        if documentHeight <= clipHeight + 2 {
            return 280
        }
        return 180
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
