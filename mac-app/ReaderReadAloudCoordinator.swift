import AVFoundation
import Cocoa

final class ReaderReadAloudCoordinator {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func toggleFromToolbar() {
        guard !owner.isReadAloudLoading else { return }
        if owner.isReadAloudPaused {
            resumeFromToolbar()
        } else if owner.isReadAloudActive {
            pauseFromToolbar()
        } else {
            startFromToolbar()
        }
    }

    func startFromToolbar() {
        guard owner.canStartReadAloudWithLocalTTS() else { return }
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(owner.readAloudAdvanceMode == .manual)
        guard owner.currentDocumentKind == .pdf else {
            owner.startWebReadAloudFromToolbar()
            return
        }
        beginLoading()
        owner.readCurrentPDFPageRemainderAndContinue(startAtPageTop: false)
    }

    func pauseFromToolbar() {
        guard owner.isReadAloudActive else { return }
        owner.readAloudState.pausePlayback()
        SpeechPlaybackCoordinator.shared.pauseSpeaking()
        owner.vocabularySpeechSynthesizer.pauseSpeaking(at: AVSpeechBoundary.immediate)
        owner.updateReadAloudButton()
    }

    func resumeFromToolbar() {
        guard owner.isReadAloudActive else { return }
        owner.readAloudState.resumePlayback()
        SpeechPlaybackCoordinator.shared.resumeSpeaking()
        owner.vocabularySpeechSynthesizer.continueSpeaking()
        owner.updateReadAloudButton()
        resumePendingIfNeeded(trigger: .userAdvance)
    }

    func stopImmediately() {
        resetState()
        SpeechPlaybackCoordinator.shared.stopSpeaking()
        owner.vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        resetPDFTracking()
        owner.clearTemporaryReadAloudUnderline()
    }

    func finishFromToolbar() {
        resetState()
        resetPDFTracking()
        owner.restoreTitleAfterSpeechPlayback()
    }

    func beginLoading() {
        owner.readAloudState.beginLoading()
        clearUserSelectionForReadAloudStart()
        owner.updateReadAloudButton()
    }

    func handleStartResult(didUseLocalTTS: Bool) {
        owner.readAloudState.markPlaying()
        owner.updateReadAloudButton()
        guard !didUseLocalTTS else { return }
        finishFromToolbar()
        if SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) == nil {
            owner.showMissingSpeechRuntimeAlert()
        } else if let error = SpeechPlaybackCoordinator.shared.consumeLastSynthesisError() {
            owner.showSpeechPlaybackFailureAlert(error: error)
        } else {
            owner.showSpeechPlaybackFailureAlert()
        }
    }

    func replayCurrentSegment() {
        guard owner.isReadAloudActive, !owner.isReadAloudLoading else { return }
        owner.readAloudState.resumePlayback()
        owner.updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayCurrentSegment()
    }

    func advanceSegment() {
        guard owner.isReadAloudActive, !owner.isReadAloudLoading else { return }
        owner.readAloudState.resumePlayback()
        owner.updateReadAloudButton()
        if resumePendingFromFloatingAdvanceIfNeeded() {
            return
        }
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            resumePendingIfNeeded(trigger: .userAdvance)
            return
        }
        SpeechPlaybackCoordinator.shared.advanceToNextSegment()
    }

    func replayPreviousSegment() {
        guard owner.isReadAloudActive, !owner.isReadAloudLoading, owner.canReadAloudGoPrevious else { return }
        owner.readAloudState.resumePlayback()
        owner.updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayPreviousSegment()
    }

    func toggleAdvanceMode() {
        owner.readAloudAdvanceMode = owner.readAloudAdvanceMode.toggled
        owner.readAloudAdvanceMode.save()
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(owner.readAloudAdvanceMode == .manual)
        if owner.readAloudAdvanceMode == .automatic, owner.isReadAloudPaused {
            owner.readAloudState.resumePlayback()
            resumePendingIfNeeded()
        }
        owner.updateReadAloudButton()
        owner.updateReadAloudFloatingControl()
    }

    func pauseForManualAdvance() {
        guard owner.readAloudAdvanceMode == .manual else { return }
        owner.readAloudState.pausePlayback()
        owner.updateReadAloudButton()
    }

    func resumePendingIfNeeded(trigger: ReaderWindowController.ReadAloudContinuationTrigger = .automatic) {
        owner.resumePendingPDFReadAloudIfNeeded(trigger: trigger)
        owner.resumePendingWebReadAloudIfNeeded(trigger: trigger)
    }

    func shouldPauseBeforeContinuation(trigger: ReaderWindowController.ReadAloudContinuationTrigger) -> Bool {
        owner.readAloudAdvanceMode == .manual && trigger == .automatic
    }

    func deferContinuationIfNeeded(
        trigger: ReaderWindowController.ReadAloudContinuationTrigger,
        setPending: () -> Void
    ) -> Bool {
        if shouldPauseBeforeContinuation(trigger: trigger) {
            setPending()
            pauseForManualAdvance()
            return true
        }
        guard !owner.isReadAloudPaused else {
            setPending()
            return true
        }
        return false
    }

    private func resumePendingFromFloatingAdvanceIfNeeded() -> Bool {
        if owner.currentDocumentKind == .pdf, owner.pendingReadAloudPDFContinuation != nil {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            owner.resumePendingPDFReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        if owner.currentDocumentKind != .pdf, owner.pendingReadAloudWebContinuation {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            owner.resumePendingWebReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        return false
    }

    private func clearUserSelectionForReadAloudStart() {
        owner.clearPDFSelectionState()
        owner.pdfView.clearSelection()
        guard owner.currentDocumentKind != .pdf, owner.webView?.isHidden == false else { return }
        owner.webView?.evaluateJavaScript("""
        (() => {
          if (window.leafReaderClearSelectionVisualOnly) {
            window.leafReaderClearSelectionVisualOnly();
          } else {
            const selection = window.getSelection && window.getSelection();
            if (selection) selection.removeAllRanges();
          }
        })();
        """)
    }

    private func resetState() {
        owner.readAloudState.stopPlayback()
        owner.updateReadAloudButton()
    }

    private func resetPDFTracking() {
        owner.resetReadAloudPDFProgress()
        owner.lastReadAloudAISource = nil
        owner.lastReadAloudLinkedWordID = nil
        owner.lastReadAloudSoftHintKey = nil
        owner.dismissReadAloudSoftHint()
        owner.pendingReadAloudPDFContinuation = nil
        owner.pendingReadAloudWebContinuation = false
    }
}
