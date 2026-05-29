import Cocoa
import PDFKit

extension ReaderWindowController {
    var readAloudOriginalTitle: String? {
        get { readAloudState.originalTitle }
        set { readAloudState.originalTitle = newValue }
    }

    var readAloudOriginalToolTip: String? {
        get { readAloudState.originalToolTip }
        set { readAloudState.originalToolTip = newValue }
    }

    var temporaryReadAloudUnderlineAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] {
        get { readAloudState.temporaryUnderlineAnnotations }
        set { readAloudState.temporaryUnderlineAnnotations = newValue }
    }

    var readAloudPDFPages: [PDFPage] {
        get { readAloudState.pdfPages }
        set { readAloudState.pdfPages = newValue }
    }

    var readAloudPDFPageTextCache: [Int: String] {
        get { readAloudState.pdfPageTextCache }
        set { readAloudState.pdfPageTextCache = newValue }
    }

    var readAloudPDFCandidatePageIndex: Int {
        get { readAloudState.pdfCandidatePageIndex }
        set { readAloudState.pdfCandidatePageIndex = newValue }
    }

    var readAloudPDFSearchLocation: Int {
        get { readAloudState.pdfSearchLocation }
        set { readAloudState.pdfSearchLocation = newValue }
    }

    var readAloudPageLockedAtTopIndex: Int? {
        get { readAloudState.pageLockedAtTopIndex }
        set { readAloudState.pageLockedAtTopIndex = newValue }
    }

    var lastReadAloudProgressPageIndex: Int? {
        get { readAloudState.lastProgressPageIndex }
        set { readAloudState.lastProgressPageIndex = newValue }
    }

    var lastReadAloudAISource: AIConversationSourceLocation? {
        get { readAloudState.lastAISource }
        set { readAloudState.lastAISource = newValue }
    }

    var lastReadAloudLinkedWordID: String? {
        get { readAloudState.lastLinkedWordID }
        set { readAloudState.lastLinkedWordID = newValue }
    }

    var readAloudSoftHintView: ReadAloudSoftHintView? {
        get { readAloudState.softHintView }
        set { readAloudState.softHintView = newValue }
    }

    var readAloudSoftHintDismissWorkItem: DispatchWorkItem? {
        get { readAloudState.softHintDismissWorkItem }
        set { readAloudState.softHintDismissWorkItem = newValue }
    }

    var lastReadAloudSoftHintKey: String? {
        get { readAloudState.lastSoftHintKey }
        set { readAloudState.lastSoftHintKey = newValue }
    }

    var readAloudSoftHintCenterXConstraint: NSLayoutConstraint? {
        get { readAloudState.softHintCenterXConstraint }
        set { readAloudState.softHintCenterXConstraint = newValue }
    }

    var readAloudFloatingControlView: ReadAloudFloatingControlView? {
        get { readAloudState.floatingControlView }
        set { readAloudState.floatingControlView = newValue }
    }

    var readAloudFloatingControlWindow: NSWindow? {
        get { readAloudState.floatingControlWindow }
        set { readAloudState.floatingControlWindow = newValue }
    }

    var pendingReadAloudPDFContinuation: PendingReadAloudPDFContinuation? {
        get { readAloudState.pendingPDFContinuation }
        set { readAloudState.pendingPDFContinuation = newValue }
    }

    var pendingReadAloudWebContinuation: Bool {
        get { readAloudState.pendingWebContinuation }
        set { readAloudState.pendingWebContinuation = newValue }
    }

    var readAloudSpeechLanguageHint: AISettingsStore.SpeechLanguageHint? {
        get { readAloudState.speechLanguageHint }
        set { readAloudState.speechLanguageHint = newValue }
    }

    var readAloudAdvanceMode: ReadAloudAdvanceMode {
        get { readAloudState.advanceMode }
        set { readAloudState.advanceMode = newValue }
    }

    var isReadAloudActive: Bool {
        get { readAloudState.isActive }
        set { readAloudState.isActive = newValue }
    }

    var isReadAloudPaused: Bool {
        get { readAloudState.isPaused }
        set { readAloudState.isPaused = newValue }
    }

    var isReadAloudLoading: Bool {
        get { readAloudState.isLoading }
        set { readAloudState.isLoading = newValue }
    }

    var canReadAloudGoPrevious: Bool {
        get { readAloudState.canGoPrevious }
        set { readAloudState.canGoPrevious = newValue }
    }
}
