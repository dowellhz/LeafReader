import AVFoundation
import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
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
    static let embeddingControlStateDefaultsKey = "embeddingControlState"
    static let minimumReadablePDFScale: CGFloat = 1.0
    static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")
    static let readAloudLanguageProbePageLimit = 3

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
    lazy var vocabularySpeechCoordinator = VocabularySpeechCoordinator(
        synthesizer: vocabularySpeechSynthesizer,
        owner: self
    )
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
    var notesButton: NSButton!
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
    var storedReadingNotes: [ReadingNote] = []
    var readingNotePanelControllers: [String: ReadingNotePanelController] = [:]
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
    var pendingAIPanelExpansionAction: (() -> Void)?
    var pendingAISourceClickWorkItem: DispatchWorkItem?
    var readAloudOriginalTitle: String?
    var readAloudOriginalToolTip: String?
    var temporaryReadAloudUnderlineAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var readAloudPDFPages: [PDFPage] = []
    var readAloudPDFPageTextCache: [Int: String] = [:]
    var readAloudPDFCandidatePageIndex = 0
    var readAloudPDFSearchLocation = 0
    var readAloudPageLockedAtTopIndex: Int?
    var lastReadAloudAISource: AIConversationSourceLocation?
    var lastReadAloudLinkedWordID: String?
    var readAloudSoftHintView: ReadAloudSoftHintView?
    var readAloudSoftHintDismissWorkItem: DispatchWorkItem?
    var lastReadAloudSoftHintKey: String?
    var readAloudSoftHintCenterXConstraint: NSLayoutConstraint?
    var readAloudFloatingControlView: ReadAloudFloatingControlView?
    var readAloudFloatingControlWindow: NSWindow?
    var pendingReadAloudPDFContinuation: PendingReadAloudPDFContinuation?
    var pendingReadAloudWebContinuation = false
    var readAloudSpeechLanguageHint: AISettingsStore.SpeechLanguageHint?
    var readAloudAdvanceMode = ReadAloudAdvanceMode.load()
    var isReadAloudActive = false
    var isReadAloudPaused = false
    var isReadAloudLoading = false
    var canReadAloudGoPrevious = false
    var currentVocabularyExportRecords: [VocabularyExportRecord] = []
    var didRegisterSelectionObserver = false
    var isRestoringSession = false
    var isEditingZoomField = false
    var isEditingPageField = false
    var isAIPanelCollapsed = true
    var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    var aiSettingsPanelController: AISettingsPanelController?
    var recentDocumentsPanelController: RecentDocumentsPanelController?
    var readingNotesPanelController: ReadingNotesPanelController?
    var vocabularyPanelController: VocabularyPanelController!
    let vocabularyReviewSession = VocabularyReviewSession()
    var aiHandleLeadingConstraint: NSLayoutConstraint!
    var aiPanelWidthConstraint: NSLayoutConstraint!
    var localEventMonitor: Any?

    override init(window: NSWindow?) {
        super.init(window: window)
        vocabularyPanelController = VocabularyPanelController(owner: self)
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
        installSpeechProgressObserver()
        _ = vocabularySpeechCoordinator
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
        pendingAISourceClickWorkItem?.cancel()
        retrievalQueryTask?.cancel()
        pdfWordRecordsSaveTask.cancel()
        webWordRecordsSaveTask.cancel()
        vocabularyPanelController.close()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webWordClicked")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webNoteClicked")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webAISourceClicked")
        NotificationCenter.default.removeObserver(self)
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}
