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
        let textAnchor: TextQuoteAnchor?
        let context: String
        var dictionaryTags: String?
        var dictionaryFrequency: Int?
        let createdAt: Date
    }

    struct PendingWebWordRecord {
        let id: String
        let word: String
        let context: String
        let occurrenceIndex: Int?
        let scrollProgress: Double
        var dictionaryTags: String?
        var dictionaryFrequency: Int?
        let createdAt: Date
    }

    enum PendingReadAloudPDFContinuation {
        case currentScreen(startAtPageTop: Bool)
        case afterCurrentScreen
        case afterBatch(lastQueuedPage: PDFPage)
        case waitForPage(expectedPageIndex: Int?, previousPageIndex: Int?, startAtPageTop: Bool)
    }

    enum ReadAloudContinuationTrigger: Equatable {
        case automatic
        case userAdvance
    }

    static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    static let pdfTwoPageModeDefaultsKey = "pdfTwoPageMode"
    static let pdfReadingModeDefaultsKey = "pdfReadingMode"
    static let pdfMarginCropDefaultsKey = "pdfMarginCrop"
    static let fileMD5CacheDefaultsKey = "fileMD5Cache"
    static let embeddingControlStateDefaultsKey = "embeddingControlState"
    static let showsRelatedWordFormsDefaultsKey = "reader.showsRelatedWordForms"
    static let minimumReadablePDFScale: CGFloat = 1.0
    static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")
    static let readAloudLanguageProbePageLimit = 3

    var pdfView: EdgePagingPDFView!
    var webView: ReaderWebView!
    lazy var pdfReaderBackend = PDFKitReaderAdapter(view: pdfView)
    lazy var webReaderBackend = WebKitReaderAdapter(view: webView)
    let contentArea = NSView()
    let pdfContainer = ClippingView()
    let pdfDimOverlay = PassthroughOverlayView()
    let loadingOverlay = NSView()
    let loadingIndicator = NSProgressIndicator()
    let loadingLabel = NSTextField(labelWithString: "")
    let aiPanel = AIChatPanel()
    lazy var vocabularySpeechSynthesizer = AVSpeechSynthesizer()
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
    var relatedFormsButton: NSButton!
    var searchUnderlineButton: SearchUnderlineButton!
    let embeddingStatusLabel = NSTextField(labelWithString: "")
    var embeddingPauseButton: NSButton!
    var embeddingCancelButton: NSButton!
    weak var toolbarView: NSView?
    weak var bottomBarView: NSView?
    weak var zoomGroupView: NSView?
    var documentState = ReaderDocumentState()
    var accumulatedPDFTrackpadScroll: CGFloat = 0
    var lastPDFTrackpadPageTurn = Date.distantPast
    var didTurnPageForCurrentPDFTrackpadGesture = false
    var lastPDFTrackpadEdgeDirection: EdgePagingPDFView.ScrollPageDirection?
    var searchResults: [PDFSelection] = []
    var searchResultIndex = 0
    var lastSearchQuery = ""
    weak var activePDFSearchDocument: PDFDocument?
    var activePDFSearchQuery = ""
    var isPDFSearchInProgress = false
    var didRegisterPDFSearchObservers = false
    var embeddingState = ReaderEmbeddingState()
    var aiState = ReaderAIState()
    let sessionSaveTask = DebouncedTask(delay: ReaderSessionPolicy.lastPositionSaveDelay)
    var vocabularyState = ReaderVocabularyState()
    var notesState = ReaderNotesState()
    let pdfWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    let webWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    var readAloudState = ReaderReadAloudState()
    var didRegisterSelectionObserver = false
    var isEditingZoomField = false
    var isEditingPageField = false
    var aiSettingsPanelController: AISettingsPanelController?
    var recentDocumentsPanelController: RecentDocumentsPanelController?
    var readingNotesPanelController: ReadingNotesPanelController?
    var vocabularyPanelController: VocabularyPanelController!
    lazy var aiPanelCoordinator = ReaderAIPanelCoordinator(owner: self)
    lazy var selectionCoordinator = ReaderSelectionCoordinator(owner: self)
    lazy var selectionToolbarCoordinator = SelectionToolbarCoordinator(owner: self)
    lazy var readAloudCoordinator = ReaderReadAloudCoordinator(owner: self)
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
        window.backgroundColor = ReaderTheme.selected.chromeBackgroundColor
        window.setFrameAutosaveName("LeafReaderClean")
        window.center()
        let dropContentView = ReaderDropContentView(frame: window.contentView?.bounds ?? .zero)
        dropContentView.autoresizingMask = [.width, .height]
        window.contentView = dropContentView

        self.init(window: window)
        dropContentView.readerWindowController = self
        window.readerWindowController = self
        window.delegate = self
        LaunchPerformanceTracker.shared.mark("windowShell")
        buildUI()
        LaunchPerformanceTracker.shared.mark("buildUI")
        installSpeechProgressObserver()
        LaunchPerformanceTracker.shared.mark("speechObserver")
    }

    deinit {
        activeDocumentLoadCancellationToken?.cancel()
        pdfTextSnapshotCancellationToken?.cancel()
        releaseCurrentOwnedWebResource()
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
