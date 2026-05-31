import Cocoa

extension ReaderWindowController {
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

    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] {
        get { documentState.pdfTOCDestinations }
        set { documentState.pdfTOCDestinations = newValue }
    }

    var pdfTOCGeneration: Int {
        get { documentState.pdfTOCGeneration }
        set { documentState.pdfTOCGeneration = newValue }
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

    var isRestoringSession: Bool {
        get { documentState.isRestoringSession }
        set { documentState.isRestoringSession = newValue }
    }

    func clearPDFSelectionState() {
        currentPDFSelectedText = ""
    }
}
