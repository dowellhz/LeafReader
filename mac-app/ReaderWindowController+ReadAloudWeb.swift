import Cocoa

extension ReaderWindowController {
    func startWebReadAloudFromToolbar() {
        beginReadAloudLoading()
        readCurrentWebReadAloudBatch()
    }

    private struct WebReadAloudBatch {
        let segments: [SpeechPlaybackCoordinator.ReadAloudSegment]
        let hasMore: Bool
    }

    private func readCurrentWebReadAloudBatch() {
        let script = """
        (() => {
          if (window.leafReaderPrepareReadAloudBatch) {
            return window.leafReaderPrepareReadAloudBatch();
          }
          if (window.leafReaderPrepareReadAloudSegments) {
            return { segments: window.leafReaderPrepareReadAloudSegments(), hasMore: false };
          }
          return { segments: [], hasMore: false };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            DispatchQueue.main.async {
                guard let self, self.isReadAloudActive else { return }
                let batch = Self.webReadAloudBatch(from: value)
                guard !batch.segments.isEmpty else {
                    self.finishReadAloudFromToolbar()
                    return
                }
                guard self.canReadAloudSegmentsWithAvailableRuntime(batch.segments) else {
                    self.finishReadAloudFromToolbar()
                    self.openSpeechSettingsForMissingChineseRuntime()
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

    private func continueWebReadAloudAfterBatch(hasMore: Bool) {
        guard isReadAloudActive else { return }
        guard hasMore else {
            finishReadAloudFromToolbar()
            return
        }
        if readAloudAdvanceMode == .manual {
            pendingReadAloudWebContinuation = true
            pauseReadAloudForManualAdvance()
            return
        }
        guard !isReadAloudPaused else {
            pendingReadAloudWebContinuation = true
            return
        }
        pendingReadAloudWebContinuation = false
        let script = """
        (() => {
          if (!window.leafReaderAdvanceReadAloudBatch) return { ok: false };
          return window.leafReaderAdvanceReadAloudBatch();
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, _ in
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

    func resumePendingWebReadAloudIfNeeded() {
        guard currentDocumentKind != .pdf,
              isReadAloudActive,
              !isReadAloudPaused,
              pendingReadAloudWebContinuation,
              !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() else {
            return
        }
        pendingReadAloudWebContinuation = false
        continueWebReadAloudAfterBatch(hasMore: true)
    }

    private static func webReadAloudBatch(from value: Any?) -> WebReadAloudBatch {
        if let dictionary = value as? [String: Any] {
            return WebReadAloudBatch(
                segments: webReadAloudSegments(from: dictionary["segments"]),
                hasMore: dictionary["hasMore"] as? Bool ?? false
            )
        }
        return WebReadAloudBatch(
            segments: webReadAloudSegments(from: value),
            hasMore: false
        )
    }

    private static func webReadAloudSegments(from value: Any?) -> [SpeechPlaybackCoordinator.ReadAloudSegment] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let text = (row["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let speechText = (row["speechText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
            guard !text.isEmpty, !speechText.isEmpty else { return nil }
            return SpeechPlaybackCoordinator.ReadAloudSegment(speechText: speechText, displayText: text)
        }
    }
}
