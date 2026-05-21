import AVFoundation
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

final class WindowDragTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class WindowDragImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    struct VocabularyExportRecord {
        let ids: [String]
        let word: String
        let answer: String
        let location: String
        let context: String
        let createdAt: Date
        let srs: VocabularySRSState
    }

    struct PendingPDFWordRecord {
        let id: String
        let word: String
        let pageIndex: Int
        let bounds: StoredPDFWordRect
        let context: String
        let createdAt: Date
    }

    struct PendingWebWordRecord {
        let id: String
        let word: String
        let context: String
        let occurrenceIndex: Int?
        let scrollProgress: Double
        let createdAt: Date
    }

    enum PendingReadAloudPDFContinuation {
        case currentScreen(startAtPageTop: Bool)
        case afterCurrentScreen
        case afterBatch(lastQueuedPage: PDFPage)
        case waitForPage(expectedPageIndex: Int?, previousPageIndex: Int?, startAtPageTop: Bool)
    }

    static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    static let pdfTwoPageModeDefaultsKey = "pdfTwoPageMode"
    static let pdfMarginCropDefaultsKey = "pdfMarginCrop"
    static let fileMD5CacheDefaultsKey = "fileMD5Cache"
    static let minimumReadablePDFScale: CGFloat = 1.0
    static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")

    var pdfView: EdgePagingPDFView!
    var webView: ReaderWebView!
    let contentArea = NSView()
    let pdfContainer = ClippingView()
    let pdfDimOverlay = PassthroughOverlayView()
    let loadingOverlay = NSView()
    let loadingIndicator = NSProgressIndicator()
    let loadingLabel = NSTextField(labelWithString: "")
    let aiPanel = AIChatPanel()
    let vocabularySpeechSynthesizer = AVSpeechSynthesizer()
    let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    let resizeHandle = ResizeHandleView()
    let titleLabel = WindowDragTextField(labelWithString: "Leaf Reader")
    let coverImageView = WindowDragImageView()
    let pageLabel = ClickEditableTextField(string: AppText.noPDF)
    let zoomField = ClickEditableTextField(string: "100%")
    let searchOverlay = SearchOverlayView()
    let selectionActionToolbar = SelectionActionToolbar()
    var selectionActionToolbarWindow: NSWindow?
    var fullScreenButton: NSButton!
    var coverButton: NSButton!
    var tocButton: NSButton!
    var recentButton: NSButton!
    var vocabularyButton: NSButton!
    var farthestPositionButton: NSButton!
    var prevButton: NSButton!
    var nextButton: NSButton!
    var readAloudButton: NSButton!
    var readAloudStopButton: NSButton!
    var pageLayoutButton: NSButton!
    var cropButton: NSButton!
    var searchButton: NSButton!
    var searchUnderlineButton: SearchUnderlineButton!
    let embeddingStatusLabel = NSTextField(labelWithString: "")
    var embeddingPauseButton: NSButton!
    var embeddingCancelButton: NSButton!
    weak var toolbarView: NSView?
    weak var bottomBarView: NSView?
    weak var zoomGroupView: NSView?
    var currentFileURL: URL?
    var lastSavedSessionBookmarkURL: URL?
    var currentFileMD5: String?
    var sessionStore = ReaderSessionStore(fileMD5: nil)
    var currentDocumentKind: ReaderDocumentKind = .pdf
    var documentLoadGeneration = 0
    var currentWebPlainText = ""
    var webPlainTextGeneration = 0
    var currentWebSelectedText = ""
    var currentWebSelectionContext = ""
    var currentWebSelectionOccurrenceIndex: Int?
    var currentWebSelectionRect: NSRect?
    var pendingWebProgressRestore: (generation: Int, progress: Double, zoomPercent: Int?)?
    var currentDocumentDiagnostics: [String] = []
    var currentTOCItems: [ReaderTOCItem] = []
    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] = [:]
    var pdfTOCGeneration = 0
    var webZoomPercent = 100
    var webScrollProgress: Double = 0
    var originalPDFCropBoxes: [Int: CGRect] = [:]
    var lastWebProgressSave = Date.distantPast
    var accumulatedPDFTrackpadScroll: CGFloat = 0
    var lastPDFTrackpadPageTurn = Date.distantPast
    var didTurnPageForCurrentPDFTrackpadGesture = false
    var lastPDFTrackpadEdgeDirection: EdgePagingPDFView.ScrollPageDirection?
    var lastPageIndex: Int?
    var searchResults: [PDFSelection] = []
    var searchResultIndex = 0
    var lastSearchQuery = ""
    var pdfAgentIndex: PDFDocumentAgentIndex?
    var isBuildingDocumentAgentIndex = false
    var documentAgentIndexGeneration = 0
    var pendingDocumentAgentIndexCallbacks: [() -> Void] = []
    lazy var pdfEmbeddingStore = PDFEmbeddingStore()
    let embeddingStoreQueue = DispatchQueue(label: "com.linlu.leafreader.embedding-store", qos: .utility)
    let embeddingClient = EmbeddingClient()
    let retrievalQueryClient = AIClient()
    var isPreparingPDFEmbeddings = false
    var isEmbeddingBackfillPaused = false
    var embeddingBackfillNeedsRetry = false
    var queuedEmbeddingPriorityPageIndex: Int?
    var pendingEmbeddingReadyCallbacks: [() -> Void] = []
    var embeddingBackfillGeneration = 0
    var scheduledEmbeddingCacheRestoreWorkItem: DispatchWorkItem?
    var scheduledEmbeddingWarmupWorkItem: DispatchWorkItem?
    var lastReaderInteractionAt = Date()
    let sessionSaveTask = DebouncedTask(delay: ReaderSessionPolicy.lastPositionSaveDelay)
    var suppressSearchSelectionForAIUntil = Date.distantPast
    var highlightedSelectionKeys = Set<String>()
    var aiSourceUnderlineKeys = Set<String>()
    var aiSourceLocationsByUnderlineKey: [String: AIConversationSourceLocation] = [:]
    var webAISourceLocationsByKey: [String: AIConversationSourceLocation] = [:]
    var activeAISourceUnderlines: [AIConversationSourceLocation] = []
    var storedWordRecords: [StoredPDFWordRecord] = []
    var pendingPDFWordRecords: [String: PendingPDFWordRecord] = [:]
    var pdfWordRecordStore: PDFWordRecordStore?
    var storedWebWordRecords: [StoredWebWordRecord] = []
    var pendingWebWordRecords: [String: PendingWebWordRecord] = [:]
    var webWordRecordStore: WebWordRecordStore?
    let pdfWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    let webWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    var aiConversationStore: AIConversationStore?
    var loadedAIConversation: SavedAIConversation?
    var pendingAIConversationToSave: SavedAIConversation?
    var documentPromptGeneration = 0
    var retrievalQueryTask: URLSessionDataTask?
    let aiConversationSaveTask = DebouncedTask(delay: 1.0)
    let preferredAIWidthSaveTask = DebouncedTask(delay: 0.4)
    let windowResizeLayoutTask = DebouncedTask(delay: 0.08)
    let aiPanelResizeLayoutTask = DebouncedTask(delay: 0.05)
    let vocabularyPanelReloadTask = DebouncedTask(delay: 0.04)
    var pendingAIPanelExpansionAction: (() -> Void)?
    var pendingAISourceClickWorkItem: DispatchWorkItem?
    var ttsReadingOriginalTitle: String?
    var ttsReadingOriginalToolTip: String?
    var temporaryTTSUnderlineAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var ttsReadingPDFPages: [PDFPage] = []
    var ttsReadingPDFPageTextCache: [Int: String] = [:]
    var ttsReadingPDFCandidatePageIndex = 0
    var ttsReadingPDFSearchLocation = 0
    var ttsPageLockedAtTopIndex: Int?
    var pendingReadAloudPDFContinuation: PendingReadAloudPDFContinuation?
    var isReadAloudActive = false
    var isReadAloudPaused = false
    var isReadAloudLoading = false
    var selectionSpeechCompletion: (() -> Void)?
    var shouldClearSelectionOnSpeechStart = false
    var currentVocabularyExportRecords: [VocabularyExportRecord] = []
    var didRegisterSelectionObserver = false
    var isRestoringSession = false
    var isEditingZoomField = false
    var isEditingPageField = false
    var isAIPanelCollapsed = true
    var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    var aiSettingsPanelController: AISettingsPanelController?
    var recentDocumentsPanelController: RecentDocumentsPanelController?
    weak var vocabularyPanel: NSWindow?
    var vocabularyPanelActivationObserver: NSObjectProtocol?
    var vocabularyReviewFilter: VocabularyFilter = .due
    var vocabularyReviewIndex = 0
    var vocabularyListPageIndex = 0
    var vocabularyReviewContextShown = false
    var vocabularyReviewAnswerShown = false
    var vocabularyListModeEnabled = false
    var vocabularyReviewCardKey: String?
    var vocabularyReviewCardShownAt = Date()
    var vocabularyReviewAnswerShownAt: Date?
    var vocabularyReviewDidScoreCurrentCard = false
    var vocabularyReviewBatchKeys: [String] = []
    var vocabularyReviewUndoSRSByID: [String: VocabularySRSState] = [:]
    var aiHandleLeadingConstraint: NSLayoutConstraint!
    var aiPanelWidthConstraint: NSLayoutConstraint!
    var localEventMonitor: Any?

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        let window = ReaderWindow(
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
        let dropContentView = ReaderDropContentView(frame: window.contentView?.bounds ?? .zero)
        dropContentView.autoresizingMask = [.width, .height]
        window.contentView = dropContentView

        self.init(window: window)
        dropContentView.readerWindowController = self
        window.readerWindowController = self
        window.delegate = self
        buildUI()
        installKittenTTSProgressObserver()
        vocabularySpeechSynthesizer.delegate = self
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        sessionSaveTask.cancel()
        aiConversationSaveTask.cancel()
        preferredAIWidthSaveTask.cancel()
        windowResizeLayoutTask.cancel()
        aiPanelResizeLayoutTask.cancel()
        vocabularyPanelReloadTask.cancel()
        pendingAISourceClickWorkItem?.cancel()
        retrievalQueryTask?.cancel()
        pdfWordRecordsSaveTask.cancel()
        webWordRecordsSaveTask.cancel()
        removeVocabularyPanelActivationObserver()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webWordClicked")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webAISourceClicked")
        NotificationCenter.default.removeObserver(self)
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}
