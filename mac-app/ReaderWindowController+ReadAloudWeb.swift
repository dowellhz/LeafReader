import Cocoa

extension ReaderWindowController {
    func startWebReadAloudFromToolbar() {
        beginReadAloudLoading()
        let script = """
        (() => {
          if (!window.leafReaderPrepareReadAloudSegments) return [];
          return window.leafReaderPrepareReadAloudSegments();
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            DispatchQueue.main.async {
                guard let self, self.isReadAloudActive else { return }
                let segments = Self.webReadAloudSegments(from: value)
                guard !segments.isEmpty else {
                    self.finishReadAloudFromToolbar()
                    return
                }
                guard self.canReadAloudSegmentsWithAvailableRuntime(segments) else {
                    self.finishReadAloudFromToolbar()
                    self.openSpeechSettingsForMissingKokoro()
                    return
                }
                KittenTTSPlayer.shared.speakEnglish(segments: segments) { [weak self] didUseKittenTTS in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.handleReadAloudStartResult(didUseKittenTTS: didUseKittenTTS)
                    }
                } finished: { [weak self] in
                    DispatchQueue.main.async {
                        self?.finishReadAloudFromToolbar()
                    }
                }
            }
        }
    }

    private static func webReadAloudSegments(from value: Any?) -> [KittenTTSPlayer.ReadAloudSegment] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let text = (row["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let speechText = (row["speechText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
            guard !text.isEmpty, !speechText.isEmpty else { return nil }
            return KittenTTSPlayer.ReadAloudSegment(speechText: speechText, displayText: text)
        }
    }
}
