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
        let scrollProgress: Double
        let createdAt: Date
    }

    struct PageJumpDiagnosticEntry {
        let date: Date
        let source: String
        let beforePageIndex: Int?
        let afterPageIndex: Int?
        let detail: String
    }

    static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    static let pdfTwoPageModeDefaultsKey = "pdfTwoPageMode"
    static let fileMD5CacheDefaultsKey = "fileMD5Cache"
    static let minimumReadablePDFScale: CGFloat = 1.0
    static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")

    var pdfView: EdgePagingPDFView!
    var webView: ReaderWebView!
    let contentArea = NSView()
    let pdfContainer = ClippingView()
    let pdfDimOverlay = PassthroughOverlayView()
    let aiPanel = AIChatPanel()
    let vocabularySpeechSynthesizer = AVSpeechSynthesizer()
    let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    let resizeHandle = ResizeHandleView()
    let titleLabel = NSTextField(labelWithString: "Leaf Reader")
    let coverImageView = NSImageView()
    let pageLabel = ClickEditableTextField(string: AppText.noPDF)
    let zoomField = ClickEditableTextField(string: "100%")
    let searchOverlay = SearchOverlayView()
    var fullScreenButton: NSButton!
    var coverButton: NSButton!
    var tocButton: NSButton!
    var recentButton: NSButton!
    var vocabularyButton: NSButton!
    var prevButton: NSButton!
    var nextButton: NSButton!
    var pageLayoutButton: NSButton!
    var searchButton: NSButton!
    var searchUnderlineButton: SearchUnderlineButton!
    let embeddingStatusLabel = NSTextField(labelWithString: "")
    var embeddingPauseButton: NSButton!
    var embeddingCancelButton: NSButton!
    weak var toolbarView: NSView?
    weak var bottomBarView: NSView?
    weak var zoomGroupView: NSView?
    var currentFileURL: URL?
    var currentFileMD5: String?
    var sessionStore = ReaderSessionStore(fileMD5: nil)
    var currentDocumentKind: ReaderDocumentKind = .pdf
    var currentWebPlainText = ""
    var currentWebSelectedText = ""
    var currentWebSelectionContext = ""
    var currentTOCItems: [ReaderTOCItem] = []
    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] = [:]
    var pdfTOCGeneration = 0
    var webZoomPercent = 100
    var webScrollProgress: Double = 0
    var lastWebProgressSave = Date.distantPast
    var accumulatedPDFTrackpadScroll: CGFloat = 0
    var lastPDFTrackpadPageTurn = Date.distantPast
    var didTurnPageForCurrentPDFTrackpadGesture = false
    var lastPDFTrackpadEdgeDirection: EdgePagingPDFView.ScrollPageDirection?
    var lastPageIndex: Int?
    var pageJumpDiagnostics: [PageJumpDiagnosticEntry] = []
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
    let sessionSaveTask = DebouncedTask(delay: 0.35)
    var suppressSearchSelectionForAIUntil = Date.distantPast
    var highlightedSelectionKeys = Set<String>()
    var aiSourceUnderlineKeys = Set<String>()
    var aiSourceLocationsByUnderlineKey: [String: AIConversationSourceLocation] = [:]
    var storedWordRecords: [StoredPDFWordRecord] = []
    var pendingPDFWordRecords: [String: PendingPDFWordRecord] = [:]
    var pdfWordRecordStore: PDFWordRecordStore?
    var storedWebWordRecords: [StoredWebWordRecord] = []
    var pendingWebWordRecords: [String: PendingWebWordRecord] = [:]
    var webWordRecordStore: WebWordRecordStore?
    let pdfWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    let webWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    var aiConversationStore: AIConversationStore?
    var pendingAIConversationToSave: SavedAIConversation?
    let aiConversationSaveTask = DebouncedTask(delay: 1.0)
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
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        sessionSaveTask.cancel()
        aiConversationSaveTask.cancel()
        pdfWordRecordsSaveTask.cancel()
        webWordRecordsSaveTask.cancel()
        removeVocabularyPanelActivationObserver()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollChanged")
        NotificationCenter.default.removeObserver(self)
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}
