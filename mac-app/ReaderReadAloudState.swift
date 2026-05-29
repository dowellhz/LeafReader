import Cocoa
import PDFKit

struct ReaderReadAloudState {
    var originalTitle: String?
    var originalToolTip: String?
    var temporaryUnderlineAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var pdfPages: [PDFPage] = []
    var pdfPageTextCache: [Int: String] = [:]
    var pdfCandidatePageIndex = 0
    var pdfSearchLocation = 0
    var pageLockedAtTopIndex: Int?
    var lastProgressPageIndex: Int?
    var lastAISource: AIConversationSourceLocation?
    var lastLinkedWordID: String?
    var softHintView: ReadAloudSoftHintView?
    var softHintDismissWorkItem: DispatchWorkItem?
    var lastSoftHintKey: String?
    var softHintCenterXConstraint: NSLayoutConstraint?
    var floatingControlView: ReadAloudFloatingControlView?
    var floatingControlWindow: NSWindow?
    var pendingPDFContinuation: ReaderWindowController.PendingReadAloudPDFContinuation?
    var pendingWebContinuation = false
    var speechLanguageHint: AISettingsStore.SpeechLanguageHint?
    var advanceMode = ReadAloudAdvanceMode.load()
    var isActive = false
    var isPaused = false
    var isLoading = false
    var canGoPrevious = false
}
