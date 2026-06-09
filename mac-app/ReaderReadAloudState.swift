import Cocoa
import PDFKit

struct ReaderReadAloudState {
    var originalTitle: String?
    var originalToolTip: String?
    var temporaryUnderlineAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var pdfPages: [PDFPage] = []
    var pdfPageTextCache: [Int: String] = [:]
    var pdfChromeFilter = PDFReadAloudChromeFilter.State()
    var pdfCandidatePageIndex = 0
    var pdfSearchLocation = 0
    var pageLockedAtTopIndex: Int?
    var lastProgressPageIndex: Int?
    var currentSelectionText = ""
    var lastAISource: AIConversationSourceLocation?
    var lastLinkedWordID: String?
    var softHintView: ReadAloudSoftHintView?
    var softHintDismissWorkItem: DispatchWorkItem?
    var lastSoftHintKey: String?
    var softHintCenterXConstraint: NSLayoutConstraint?
    var floatingControlView: ReadAloudFloatingControlView?
    var floatingControlWindow: NSWindow?
    var shortcutHintView: ReadAloudShortcutHintView?
    var shortcutHintWindow: NSWindow?
    var shortcutHintDismissWorkItem: DispatchWorkItem?
    var pendingPDFContinuation: ReaderWindowController.PendingReadAloudPDFContinuation?
    var pendingWebContinuation = false
    var speechLanguageHint: AISettingsStore.SpeechLanguageHint?
    var advanceMode = ReadAloudAdvanceMode.load()
    private(set) var playbackPhase: ReadAloudPlaybackPhase = .idle
    var canGoPrevious = false

    var isActive: Bool {
        get { playbackPhase.isActive }
        set {
            if newValue {
                if playbackPhase == .idle {
                    playbackPhase = .playing
                }
            } else {
                stopPlayback()
            }
        }
    }

    var isPaused: Bool {
        get { playbackPhase.isPaused }
        set {
            if newValue {
                pausePlayback()
            } else if playbackPhase == .paused {
                resumePlayback()
            }
        }
    }

    var isLoading: Bool {
        get { playbackPhase.isLoading }
        set {
            if newValue {
                applyPlaybackEvent(.startLoading)
            } else if playbackPhase == .loading {
                applyPlaybackEvent(.playbackStarted)
            }
        }
    }

    mutating func applyPlaybackEvent(_ event: ReadAloudPlaybackEvent) {
        switch event {
        case .startLoading:
            playbackPhase = .loading
            canGoPrevious = false
        case .playbackStarted:
            guard playbackPhase.isActive else { return }
            playbackPhase = .playing
        case .pause:
            guard playbackPhase.isActive else { return }
            playbackPhase = .paused
        case .resume:
            guard playbackPhase == .paused else { return }
            playbackPhase = .playing
        case .stop:
            playbackPhase = .idle
            canGoPrevious = false
            speechLanguageHint = nil
        }
    }

    mutating func beginLoading() {
        applyPlaybackEvent(.startLoading)
    }

    mutating func markPlaying() {
        applyPlaybackEvent(.playbackStarted)
    }

    mutating func pausePlayback() {
        applyPlaybackEvent(.pause)
    }

    mutating func resumePlayback() {
        applyPlaybackEvent(.resume)
    }

    mutating func stopPlayback() {
        applyPlaybackEvent(.stop)
    }
}
