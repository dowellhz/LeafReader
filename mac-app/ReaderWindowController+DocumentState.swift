import Cocoa
import PDFKit

extension ReaderWindowController {
    var pdfTextSnapshot: PDFDocumentTextSnapshot? {
        get { documentState.pdfTextSnapshot }
        set { documentState.pdfTextSnapshot = newValue }
    }

    var pdfTextSnapshotGeneration: Int {
        get { documentState.pdfTextSnapshotGeneration }
        set { documentState.pdfTextSnapshotGeneration = newValue }
    }

    var pdfTextSnapshotCancellationToken: PDFDocumentTextCancellationToken? {
        get { documentState.pdfTextSnapshotCancellationToken }
        set { documentState.pdfTextSnapshotCancellationToken = newValue }
    }

    var isPreparingPDFTextSnapshot: Bool {
        get { documentState.isPreparingPDFTextSnapshot }
        set { documentState.isPreparingPDFTextSnapshot = newValue }
    }

    var pdfTextSnapshotCallbacks: [(PDFDocumentTextSnapshot?) -> Void] {
        get { documentState.pdfTextSnapshotCallbacks }
        set { documentState.pdfTextSnapshotCallbacks = newValue }
    }

    var currentFileURL: URL? {
        get { documentState.currentFileURL }
        set { documentState.currentFileURL = newValue }
    }

    var lastSavedSessionBookmarkURL: URL? {
        get { documentState.lastSavedSessionBookmarkURL }
        set { documentState.lastSavedSessionBookmarkURL = newValue }
    }

    var currentFileMD5: String? {
        get { documentState.currentFileMD5 }
        set { documentState.currentFileMD5 = newValue }
    }

    var sessionStore: ReaderSessionStore {
        get { documentState.sessionStore }
        set { documentState.sessionStore = newValue }
    }

    var currentDocumentKind: ReaderDocumentKind {
        get { documentState.currentDocumentKind }
        set { documentState.currentDocumentKind = newValue }
    }

    var documentLoadGeneration: Int {
        get { documentState.documentLoadGeneration }
        set { documentState.documentLoadGeneration = newValue }
    }

    var activeDocumentLoadCancellationToken: DocumentLoadCancellationToken? {
        get { documentState.activeDocumentLoadCancellationToken }
        set { documentState.activeDocumentLoadCancellationToken = newValue }
    }

    var currentPDFSelectedText: String {
        get { documentState.currentPDFSelectedText }
        set { documentState.currentPDFSelectedText = newValue }
    }

    var currentWebPlainText: String {
        get { documentState.currentWebPlainText }
        set { documentState.currentWebPlainText = newValue }
    }

    var webPlainTextGeneration: Int {
        get { documentState.webPlainTextGeneration }
        set { documentState.webPlainTextGeneration = newValue }
    }

    var currentWebSelectedText: String {
        get { documentState.currentWebSelectedText }
        set { documentState.currentWebSelectedText = newValue }
    }

    var currentWebSelectionContext: String {
        get { documentState.currentWebSelectionContext }
        set { documentState.currentWebSelectionContext = newValue }
    }

    var currentWebSelectionOccurrenceIndex: Int? {
        get { documentState.currentWebSelectionOccurrenceIndex }
        set { documentState.currentWebSelectionOccurrenceIndex = newValue }
    }

    var currentWebSelectionRect: NSRect? {
        get { documentState.currentWebSelectionRect }
        set { documentState.currentWebSelectionRect = newValue }
    }

    var pendingWebProgressRestore: (generation: Int, progress: Double, zoomPercent: Int?)? {
        get { documentState.pendingWebProgressRestore }
        set { documentState.pendingWebProgressRestore = newValue }
    }

    var currentDocumentDiagnostics: [String] {
        get { documentState.currentDocumentDiagnostics }
        set { documentState.currentDocumentDiagnostics = newValue }
    }

    var currentTOCItems: [ReaderTOCItem] {
        get { documentState.currentTOCItems }
        set { documentState.currentTOCItems = newValue }
    }

    var currentOwnedWebResource: OwnedTemporaryResource? {
        get { documentState.currentOwnedWebResource }
        set { documentState.currentOwnedWebResource = newValue }
    }

    var allowedInitialWebNavigationURLs: Set<String> {
        get { documentState.allowedInitialWebNavigationURLs }
        set { documentState.allowedInitialWebNavigationURLs = newValue }
    }

    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] {
        get { documentState.pdfTOCDestinations }
        set { documentState.pdfTOCDestinations = newValue }
    }

    var pdfTOCGeneration: Int {
        get { documentState.pdfTOCGeneration }
        set { documentState.pdfTOCGeneration = newValue }
    }

    var pendingPDFTOCBuildRequest: (url: URL, displayBox: PDFDisplayBox)? {
        get { documentState.pendingPDFTOCBuildRequest }
        set { documentState.pendingPDFTOCBuildRequest = newValue }
    }

    var pendingPDFCoverThumbnailRequest: (url: URL, documentID: String?)? {
        get { documentState.pendingPDFCoverThumbnailRequest }
        set { documentState.pendingPDFCoverThumbnailRequest = newValue }
    }

    var webZoomPercent: Int {
        get { documentState.webZoomPercent }
        set { documentState.webZoomPercent = newValue }
    }

    var webScrollProgress: Double {
        get { documentState.webScrollProgress }
        set { documentState.webScrollProgress = newValue }
    }

    var originalPDFCropBoxes: [Int: CGRect] {
        get { documentState.originalPDFCropBoxes }
        set { documentState.originalPDFCropBoxes = newValue }
    }

    var lastWebProgressSave: Date {
        get { documentState.lastWebProgressSave }
        set { documentState.lastWebProgressSave = newValue }
    }

    var lastPageIndex: Int? {
        get { documentState.lastPageIndex }
        set { documentState.lastPageIndex = newValue }
    }

    var lastPersonalVocabularyPDFPageIndex: Int? {
        get { documentState.lastPersonalVocabularyPDFPageIndex }
        set { documentState.lastPersonalVocabularyPDFPageIndex = newValue }
    }

    var lastPersonalVocabularyWebProgressBucket: Int? {
        get { documentState.lastPersonalVocabularyWebProgressBucket }
        set { documentState.lastPersonalVocabularyWebProgressBucket = newValue }
    }

    var isRestoringSession: Bool {
        get { documentState.isRestoringSession }
        set { documentState.isRestoringSession = newValue }
    }

    func clearPDFSelectionState() {
        currentPDFSelectedText = ""
    }
}
