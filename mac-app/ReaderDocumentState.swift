import Cocoa

struct ReaderDocumentState {
    var currentFileURL: URL?
    var lastSavedSessionBookmarkURL: URL?
    var currentFileMD5: String?
    var sessionStore = ReaderSessionStore(fileMD5: nil)
    var currentDocumentKind: ReaderDocumentKind = .pdf
    var documentLoadGeneration = 0
    var currentPDFSelectedText = ""
    var currentWebPlainText = ""
    var webPlainTextGeneration = 0
    var currentWebSelectedText = ""
    var currentWebSelectionContext = ""
    var currentWebSelectionOccurrenceIndex: Int?
    var currentWebSelectionRect: NSRect?
    var pendingWebProgressRestore: (generation: Int, progress: Double, zoomPercent: Int?)?
    var currentDocumentDiagnostics: [String] = []
    var currentTOCItems: [ReaderTOCItem] = []
    var currentOwnedWebResource: OwnedTemporaryResource?
    var allowedInitialWebNavigationURLs: Set<String> = []
    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] = [:]
    var pdfTOCGeneration = 0
    var webZoomPercent = 100
    var webScrollProgress: Double = 0
    var originalPDFCropBoxes: [Int: CGRect] = [:]
    var lastWebProgressSave = Date.distantPast
    var lastPageIndex: Int?
    var lastPersonalVocabularyPDFPageIndex: Int?
    var lastPersonalVocabularyWebProgressBucket: Int?
    var isRestoringSession = false
}
