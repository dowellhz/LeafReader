import Cocoa
import PDFKit
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
        stopReadAloudFromToolbar()
    }

    private func startReadAloudFromToolbar() {
        guard canStartReadAloudWithLocalTTS() else { return }
        guard currentDocumentKind == .pdf else {
            startWebReadAloudFromToolbar()
            return
        }
        beginReadAloudLoading()
        readCurrentPDFPageRemainderAndContinue()
    }

    private func pauseReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        isReadAloudPaused = true
        KittenTTSPlayer.shared.pauseSpeaking()
        vocabularySpeechSynthesizer.pauseSpeaking(at: AVSpeechBoundary.immediate)
        updateReadAloudButton()
    }

    private func resumeReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        isReadAloudPaused = false
        KittenTTSPlayer.shared.resumeSpeaking()
        vocabularySpeechSynthesizer.continueSpeaking()
        updateReadAloudButton()
    }

    private func stopReadAloudFromToolbar() {
        resetReadAloudState()
        KittenTTSPlayer.shared.stopSpeaking()
        vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        resetReadAloudPDFTracking()
        clearTemporaryTTSUnderline()
    }

    private func readCurrentPDFPageRemainderAndContinue() {
        guard isReadAloudActive, !isReadAloudPaused else { return }
        guard let batch = pdfReadAloudBatchFromCurrentScreen() else {
            continueReadAloudAfterCurrentPDFScreen()
            return
        }

        ttsReadingPDFPages = batch.pages
        ttsReadingPDFPageIndex = 0
        ttsReadingPDFSearchLocation = 0

        KittenTTSPlayer.shared.speakEnglish(segments: batch.segments) { [weak self] didUseKittenTTS in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleReadAloudStartResult(didUseKittenTTS: didUseKittenTTS)
            }
        } finished: { [weak self] in
            DispatchQueue.main.async {
                self?.continueReadAloudAfterPDFBatch(lastQueuedPage: batch.lastPage)
            }
        }
    }

    private func continueReadAloudAfterPDFBatch(lastQueuedPage: PDFPage) {
        guard isReadAloudActive, !isReadAloudPaused else { return }
        guard let document = pdfView.document else {
            continueReadAloudAfterCurrentPDFScreen()
            return
        }
        let lastQueuedIndex = document.index(for: lastQueuedPage)
        guard lastQueuedIndex != NSNotFound else {
            continueReadAloudAfterCurrentPDFScreen()
            return
        }
        let nextIndex = lastQueuedIndex + 1
        guard nextIndex < document.pageCount,
              let nextPage = document.page(at: nextIndex) else {
            finishReadAloudFromToolbar()
            return
        }
        pdfView.go(to: nextPage)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.readCurrentPDFPageRemainderAndContinue()
        }
    }

    private func continueReadAloudAfterCurrentPDFScreen() {
        guard isReadAloudActive, !isReadAloudPaused else { return }
        guard let before = currentPageIndex() else {
            finishReadAloudFromToolbar()
            return
        }
        nextPage()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isReadAloudActive else { return }
            if self.currentPageIndex() == before {
                self.finishReadAloudFromToolbar()
            } else {
                self.readCurrentPDFPageRemainderAndContinue()
            }
        }
    }

    private func finishReadAloudFromToolbar() {
        resetReadAloudState()
        resetReadAloudPDFTracking()
    }

    private func beginReadAloudLoading() {
        isReadAloudActive = true
        isReadAloudPaused = false
        isReadAloudLoading = true
        clearUserSelectionForReadAloudStart()
        updateReadAloudButton()
    }

    private func clearUserSelectionForReadAloudStart() {
        pdfView.clearSelection()
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

    private func handleReadAloudStartResult(didUseKittenTTS: Bool) {
        isReadAloudLoading = false
        updateReadAloudButton()
        guard !didUseKittenTTS else { return }
        finishReadAloudFromToolbar()
        showMissingSpeechRuntimeAlert()
    }

    private func resetReadAloudState() {
        isReadAloudActive = false
        isReadAloudPaused = false
        isReadAloudLoading = false
        updateReadAloudButton()
    }

    private func resetReadAloudPDFTracking() {
        ttsReadingPDFPages.removeAll()
        ttsReadingPDFPageIndex = 0
        ttsReadingPDFSearchLocation = 0
    }

    func updateReadAloudButton() {
        guard let readAloudButton else { return }
        readAloudButton.title = isReadAloudLoading
            ? AppText.localized("加载中", "Loading")
            : (isReadAloudPaused
            ? AppText.localized("继续", "Resume")
            : (isReadAloudActive ? AppText.localized("暂停", "Pause") : AppText.localized("朗读", "Read")))
        readAloudButton.isEnabled = !isReadAloudLoading
        setSystemImage(
            isReadAloudLoading ? "hourglass" : (isReadAloudPaused ? "play.fill" : (isReadAloudActive ? "pause.fill" : "speaker.wave.2")),
            on: readAloudButton,
            accessibilityDescription: readAloudButton.title
        )
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
    }

    private func pdfTextFromVisibleTopToPageEnd(of page: PDFPage) -> String? {
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let visibleRect = pdfView.convert(pdfView.bounds, to: page)
            .intersection(pageBounds)
        let verticalChromeInset = max(24, pageBounds.height * 0.06)
        let contentTopY = pageBounds.maxY - verticalChromeInset
        let contentBottomY = pageBounds.minY + verticalChromeInset
        let topY = visibleRect.isNull
            ? contentTopY
            : min(max(visibleRect.maxY, contentBottomY), contentTopY)
        let unreadRect = CGRect(
            x: pageBounds.minX,
            y: contentBottomY,
            width: pageBounds.width,
            height: max(0, topY - contentBottomY)
        )
        let selection = unreadRect.width > 0 && unreadRect.height > 0
            ? page.selection(for: unreadRect)
            : nil
        let rawText = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? page.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let text = strippedPDFChromeForReadAloud(rawText, page: page)
        guard Self.readAloudWordCount(in: text) >= 4 else { return nil }
        return text.isEmpty ? nil : text
    }

    private static func readAloudWordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private struct PDFReadAloudBatch {
        let pages: [PDFPage]
        let segments: [KittenTTSPlayer.ReadAloudSegment]
        let lastPage: PDFPage
    }

    private func pdfReadAloudBatchFromCurrentScreen() -> PDFReadAloudBatch? {
        guard let page = pdfView.currentPage,
              let text = pdfTextFromVisibleTopToPageEnd(of: page),
              let pageIndex = pdfView.document?.index(for: page),
              pageIndex != NSNotFound else {
            return nil
        }
        var pages = [page]
        var pageTexts = [PDFReadAloudPageText(pageIndex: pageIndex, text: text)]

        if let nextPage = nextPDFPage(after: page),
           let nextPageIndex = pdfView.document?.index(for: nextPage),
           nextPageIndex != NSNotFound,
           let nextText = pdfTextForFullPageReadAloud(nextPage) {
            pages.append(nextPage)
            pageTexts.append(PDFReadAloudPageText(pageIndex: nextPageIndex, text: nextText))
        }

        let segments = Self.pdfReadAloudSegments(from: pageTexts)
        guard !segments.isEmpty else { return nil }
        return PDFReadAloudBatch(
            pages: pages,
            segments: segments,
            lastPage: pages.last ?? page
        )
    }

    private struct PDFReadAloudPageText {
        let pageIndex: Int
        let text: String
    }

    private static func pdfReadAloudSegments(from pageTexts: [PDFReadAloudPageText]) -> [KittenTTSPlayer.ReadAloudSegment] {
        var segments: [KittenTTSPlayer.ReadAloudSegment] = []
        for pageText in pageTexts {
            let text = pageText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for segment in KittenTTSPlayer.readAloudSegments(for: text) {
                segments.append(KittenTTSPlayer.ReadAloudSegment(
                    speechText: segment,
                    displayText: segment,
                    pageIndex: pageText.pageIndex
                ))
            }
        }
        return segments
    }

    private static func pdfReadAloudTextEndsAtSentenceBoundary(_ text: String) -> Bool {
        let closingCharacters = CharacterSet(charactersIn: "\"'”’)]}）】》」』")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            let scalarString = String(trimmed[previous])
            if scalarString.unicodeScalars.allSatisfy({ closingCharacters.contains($0) }) {
                index = previous
                continue
            }
            return ".!?。！？…".contains(trimmed[previous])
        }
        return false
    }

    private func nextPDFPage(after page: PDFPage) -> PDFPage? {
        guard let document = pdfView.document else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, pageIndex + 1 < document.pageCount else { return nil }
        return document.page(at: pageIndex + 1)
    }

    private func pdfTextForFullPageReadAloud(_ page: PDFPage) -> String? {
        let rawText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = strippedPDFChromeForReadAloud(rawText, page: page)
        guard Self.readAloudWordCount(in: text) >= 4 else { return nil }
        return text.isEmpty ? nil : text
    }

    private func strippedPDFChromeForReadAloud(_ text: String, page: PDFPage) -> String {
        guard let document = pdfView.document else {
            return ReaderAIContextBuilder.stripPDFPageChrome(
                from: text,
                previousText: "",
                nextText: "",
                title: titleLabel.stringValue
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pageIndex = document.index(for: page)
        let previousText = pageIndex > 0 ? document.page(at: pageIndex - 1)?.string ?? "" : ""
        let nextText = pageIndex + 1 < document.pageCount ? document.page(at: pageIndex + 1)?.string ?? "" : ""
        return ReaderAIContextBuilder.stripPDFPageChrome(
            from: text,
            previousText: previousText,
            nextText: nextText,
            title: titleLabel.stringValue
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startWebReadAloudFromToolbar() {
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

    private func canStartReadAloudWithLocalTTS() -> Bool {
        guard let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID),
              runtime.isUsableForReadAloud,
              SpeechRuntimeResourceManager.isInstalled(runtime) else {
            showMissingSpeechRuntimeAlert()
            return false
        }
        return true
    }

    private func showMissingSpeechRuntimeAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("需要下载朗读模型", "Read Aloud Model Required")
        alert.informativeText = AppText.localized(
            "朗读需要先下载 Kokoro 或 KittenTTS 模型。",
            "Read aloud requires downloading a Kokoro or KittenTTS speech model first."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.localized("打开朗读设置", "Open Read Aloud Settings"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openSettingsPanel(tab: .speech)
        }
    }
}

extension ReaderWindowController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else { return }
        clearSelectionForSpeechStartIfNeeded()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else {
            return
        }
        if let completion = selectionSpeechCompletion {
            selectionSpeechCompletion = nil
            completion()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard synthesizer === vocabularySpeechSynthesizer else { return }
        shouldClearSelectionOnSpeechStart = false
        selectionSpeechCompletion = nil
    }
}
