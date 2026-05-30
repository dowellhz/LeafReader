import Cocoa

extension ReaderWindowController {
    func startWebReadAloudFromToolbar() {
        beginReadAloudLoading()
        readCurrentWebReadAloudBatch()
    }

    private func readCurrentWebReadAloudBatch() {
        webView.evaluateJavaScript(WebReadAloudBatchParser.prepareBatchScript) { [weak self] value, _ in
            DispatchQueue.main.async {
                guard let self, self.isReadAloudActive else { return }
                let batch = WebReadAloudBatchParser.batch(from: value)
                guard !batch.segments.isEmpty else {
                    self.finishReadAloudFromToolbar()
                    return
                }
                guard self.canReadAloudSegmentsWithAvailableRuntime(batch.segments) else {
                    self.finishReadAloudFromToolbar()
                    self.showMissingChineseSpeechRuntimeAlert()
                    return
                }
                let segments = self.readAloudSegmentsWithCurrentLanguageHint(batch.segments)
                SpeechPlaybackCoordinator.shared.speakText(segments: segments) { [weak self] didUseLocalTTS in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.handleReadAloudStartResult(didUseLocalTTS: didUseLocalTTS)
                    }
                } finished: { [weak self] in
                    DispatchQueue.main.async {
                        self?.continueWebReadAloudAfterBatch(hasMore: batch.hasMore)
                    }
                }
            }
        }
    }

    private func continueWebReadAloudAfterBatch(
        hasMore: Bool,
        trigger: ReadAloudContinuationTrigger = .automatic
    ) {
        guard isReadAloudActive else { return }
        guard hasMore else {
            finishReadAloudFromToolbar()
            return
        }
        if deferReadAloudContinuationIfNeeded(trigger: trigger, setPending: {
            pendingReadAloudWebContinuation = true
        }) {
            return
        }
        pendingReadAloudWebContinuation = false
        webView.evaluateJavaScript(WebReadAloudBatchParser.advanceBatchScript) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard let self,
                      self.isReadAloudActive,
                      !self.isReadAloudPaused else {
                    return
                }
                self.readCurrentWebReadAloudBatch()
            }
        }
    }

    func resumePendingWebReadAloudIfNeeded(trigger: ReadAloudContinuationTrigger = .automatic) {
        guard currentDocumentKind != .pdf,
              isReadAloudActive,
              !isReadAloudPaused,
              pendingReadAloudWebContinuation,
              !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() else {
            return
        }
        pendingReadAloudWebContinuation = false
        continueWebReadAloudAfterBatch(hasMore: true, trigger: trigger)
    }

    func skipReadAloudToNextWebPage() {
        guard isReadAloudActive else { return }
        SpeechPlaybackCoordinator.shared.stopSpeaking()
        pendingReadAloudWebContinuation = false
        readAloudState.resumePlayback()
        beginReadAloudLoading()
        scrollWebPage(direction: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.isReadAloudActive, self.currentDocumentKind != .pdf else { return }
            self.readCurrentWebReadAloudBatch()
        }
    }
}
