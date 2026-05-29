import Cocoa
import AVFoundation

extension ReaderWindowController {
    @objc func toggleReadAloudFromToolbar() {
        guard !isReadAloudLoading else { return }
        if isReadAloudPaused {
            resumeReadAloudFromToolbar()
        } else if isReadAloudActive {
            pauseReadAloudFromToolbar()
        } else {
            startReadAloudFromToolbar()
        }
    }

    @objc func stopReadAloudFromToolbarAction() {
        stopReadAloudImmediately()
    }

    private func startReadAloudFromToolbar() {
        guard canStartReadAloudWithLocalTTS() else { return }
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(readAloudAdvanceMode == .manual)
        guard currentDocumentKind == .pdf else {
            startWebReadAloudFromToolbar()
            return
        }
        beginReadAloudLoading()
        readCurrentPDFPageRemainderAndContinue(startAtPageTop: false)
    }

    private func pauseReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        isReadAloudPaused = true
        SpeechPlaybackCoordinator.shared.pauseSpeaking()
        vocabularySpeechSynthesizer.pauseSpeaking(at: AVSpeechBoundary.immediate)
        updateReadAloudButton()
    }

    private func resumeReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        isReadAloudPaused = false
        SpeechPlaybackCoordinator.shared.resumeSpeaking()
        vocabularySpeechSynthesizer.continueSpeaking()
        updateReadAloudButton()
        resumePendingReadAloudIfNeeded(trigger: .userAdvance)
    }

    func stopReadAloudImmediately() {
        resetReadAloudState()
        SpeechPlaybackCoordinator.shared.stopSpeaking()
        vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        resetReadAloudPDFTracking()
        clearTemporaryReadAloudUnderline()
    }

    func finishReadAloudFromToolbar() {
        resetReadAloudState()
        resetReadAloudPDFTracking()
        restoreTitleAfterSpeechPlayback()
    }

    func beginReadAloudLoading() {
        isReadAloudActive = true
        isReadAloudPaused = false
        isReadAloudLoading = true
        canReadAloudGoPrevious = false
        clearUserSelectionForReadAloudStart()
        updateReadAloudButton()
    }

    private func clearUserSelectionForReadAloudStart() {
        pdfView.clearSelection()
        guard currentDocumentKind != .pdf, webView?.isHidden == false else { return }
        webView?.evaluateJavaScript("""
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

    func handleReadAloudStartResult(didUseLocalTTS: Bool) {
        isReadAloudLoading = false
        updateReadAloudButton()
        guard !didUseLocalTTS else { return }
        finishReadAloudFromToolbar()
        if SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) == nil {
            showMissingSpeechRuntimeAlert()
        } else if let error = SpeechPlaybackCoordinator.shared.consumeLastSynthesisError() {
            showSpeechPlaybackFailureAlert(error: error)
        } else {
            showSpeechPlaybackFailureAlert()
        }
    }

    private func resetReadAloudState() {
        isReadAloudActive = false
        isReadAloudPaused = false
        isReadAloudLoading = false
        canReadAloudGoPrevious = false
        readAloudSpeechLanguageHint = nil
        updateReadAloudButton()
    }

    private func resetReadAloudPDFTracking() {
        resetReadAloudPDFProgress()
        lastReadAloudAISource = nil
        lastReadAloudLinkedWordID = nil
        lastReadAloudSoftHintKey = nil
        dismissReadAloudSoftHint()
        pendingReadAloudPDFContinuation = nil
        pendingReadAloudWebContinuation = false
    }

    func updateReadAloudButton() {
        guard let readAloudButton else { return }
        let symbolName = isReadAloudLoading
            ? "hourglass"
            : (isReadAloudPaused ? "play.fill" : (isReadAloudActive ? "pause.fill" : "speaker.wave.2"))
        readAloudButton.title = isReadAloudLoading
            ? AppText.localized("加载中", "Loading")
            : (isReadAloudPaused
            ? AppText.localized("继续", "Resume")
            : (isReadAloudActive ? AppText.localized("暂停", "Pause") : AppText.localized("朗读", "Read")))
        readAloudButton.isEnabled = !isReadAloudLoading
        setCapsuleButtonSymbol(symbolName, on: readAloudButton, accessibilityDescription: readAloudButton.title)
        readAloudButton.toolTip = isReadAloudLoading
            ? AppText.localized("正在加载朗读模型", "Loading read aloud model")
            : (isReadAloudPaused
            ? AppText.localized("继续朗读", "Resume reading")
            : (isReadAloudActive
                ? AppText.localized("暂停朗读", "Pause reading")
                : AppText.localized("从当前屏幕顶部开始朗读", "Read from the top of the current screen")))
        readAloudStopButton?.isHidden = !isReadAloudActive
        readAloudButton.needsDisplay = true
        readAloudButton.displayIfNeeded()
        updateReadAloudFloatingControl()
    }

    func resumePendingReadAloudIfNeeded(trigger: ReadAloudContinuationTrigger = .automatic) {
        resumePendingPDFReadAloudIfNeeded(trigger: trigger)
        resumePendingWebReadAloudIfNeeded(trigger: trigger)
    }

    func shouldPauseBeforeReadAloudContinuation(trigger: ReadAloudContinuationTrigger) -> Bool {
        readAloudAdvanceMode == .manual && trigger == .automatic
    }

    func deferReadAloudContinuationIfNeeded(
        trigger: ReadAloudContinuationTrigger,
        setPending: () -> Void
    ) -> Bool {
        if shouldPauseBeforeReadAloudContinuation(trigger: trigger) {
            setPending()
            pauseReadAloudForManualAdvance()
            return true
        }
        guard !isReadAloudPaused else {
            setPending()
            return true
        }
        return false
    }

}
