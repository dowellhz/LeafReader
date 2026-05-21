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
        stopReadAloudImmediately()
    }

    private func startReadAloudFromToolbar() {
        guard canStartReadAloudWithLocalTTS() else { return }
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
        resumePendingPDFReadAloudIfNeeded()
    }

    func stopReadAloudImmediately() {
        resetReadAloudState()
        KittenTTSPlayer.shared.stopSpeaking()
        vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        resetReadAloudPDFTracking()
        clearTemporaryTTSUnderline()
    }

    private func readCurrentPDFPageRemainderAndContinue(startAtPageTop: Bool) {
        guard isReadAloudActive else { return }
        guard !isReadAloudPaused else {
            pendingReadAloudPDFContinuation = .currentScreen(startAtPageTop: startAtPageTop)
            return
        }
        pendingReadAloudPDFContinuation = nil
        guard let batch = pdfReadAloudBatchFromCurrentScreen(startAtPageTop: startAtPageTop) else {
            continueReadAloudAfterCurrentPDFScreen()
            return
        }

        ttsReadingPDFPages = batch.pages
        ttsReadingPDFPageTextCache = batch.pageTextCache
        ttsReadingPDFCandidatePageIndex = 0
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
        guard isReadAloudActive else { return }
        guard !isReadAloudPaused else {
            pendingReadAloudPDFContinuation = .afterBatch(lastQueuedPage: lastQueuedPage)
            return
        }
        pendingReadAloudPDFContinuation = nil
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
        continueReadAloudFromPDFPageTop(at: nextIndex, previousPageIndex: nil)
    }

    private func continueReadAloudAfterCurrentPDFScreen() {
        guard isReadAloudActive else { return }
        guard !isReadAloudPaused else {
            pendingReadAloudPDFContinuation = .afterCurrentScreen
            return
        }
        pendingReadAloudPDFContinuation = nil
        guard let before = currentPageIndex() else {
            finishReadAloudFromToolbar()
            return
        }
        let nextIndex = before + 1
        continueReadAloudFromPDFPageTop(at: nextIndex, previousPageIndex: before)
    }

    private func finishReadAloudFromToolbar() {
        resetReadAloudState()
        resetReadAloudPDFTracking()
        restoreTitleAfterKittenTTS()
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
        resetTTSReadingPDFProgress()
        pendingReadAloudPDFContinuation = nil
    }

    private func waitForPDFReadAloudPageChange(
        expectedPageIndex: Int?,
        previousPageIndex: Int?,
        startAtPageTop: Bool,
        attemptsRemaining: Int = 10
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isReadAloudActive else { return }
            guard !self.isReadAloudPaused else {
                self.pendingReadAloudPDFContinuation = .waitForPage(
                    expectedPageIndex: expectedPageIndex,
                    previousPageIndex: previousPageIndex,
                    startAtPageTop: startAtPageTop
                )
                return
            }

            let current = self.currentPageIndex()
            let reachedTarget = expectedPageIndex.map { current == $0 } ?? false
            let movedFromPrevious = previousPageIndex.map { current != nil && current != $0 } ?? false
            if reachedTarget || movedFromPrevious {
                self.readCurrentPDFPageRemainderAndContinue(startAtPageTop: startAtPageTop)
                return
            }

            guard attemptsRemaining > 0 else {
                self.recoverFromPDFReadAloudPageWaitTimeout(
                    expectedPageIndex: expectedPageIndex,
                    previousPageIndex: previousPageIndex,
                    startAtPageTop: startAtPageTop
                )
                return
            }
            self.waitForPDFReadAloudPageChange(
                expectedPageIndex: expectedPageIndex,
                previousPageIndex: previousPageIndex,
                startAtPageTop: startAtPageTop,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func recoverFromPDFReadAloudPageWaitTimeout(
        expectedPageIndex: Int?,
        previousPageIndex: Int?,
        startAtPageTop: Bool
    ) {
        if let expectedPageIndex,
           let document = pdfView.document,
           expectedPageIndex >= 0,
           expectedPageIndex < document.pageCount,
           let page = document.page(at: expectedPageIndex) {
            NSLog("LeafReader read aloud: forcing PDF page after delayed page change (target=%d)", expectedPageIndex + 1)
            goToPDFReadAloudPageTop(page)
            lastPageIndex = expectedPageIndex
            updatePageLabel()
            saveSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.isReadAloudActive else { return }
                guard !self.isReadAloudPaused else {
                    self.pendingReadAloudPDFContinuation = .waitForPage(
                        expectedPageIndex: expectedPageIndex,
                        previousPageIndex: previousPageIndex,
                        startAtPageTop: startAtPageTop
                    )
                    return
                }
                self.readCurrentPDFPageRemainderAndContinue(startAtPageTop: startAtPageTop)
            }
            return
        }

        if let previousPageIndex,
           currentPageIndex() == previousPageIndex {
            finishReadAloudFromToolbar()
            return
        }
        readCurrentPDFPageRemainderAndContinue(startAtPageTop: startAtPageTop)
    }

    private func goToPDFReadAloudPageTop(_ page: PDFPage) {
        let bounds = page.bounds(for: pdfView.displayBox)
        let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
        pdfView.go(to: destination)
        if let pageIndex = pdfView.document?.index(for: page), pageIndex != NSNotFound {
            ttsPageLockedAtTopIndex = pageIndex
        }
    }

    private func continueReadAloudFromPDFPageTop(at pageIndex: Int, previousPageIndex: Int?) {
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            finishReadAloudFromToolbar()
            return
        }
        goToPDFReadAloudPageTop(page)
        waitForPDFReadAloudPageChange(
            expectedPageIndex: pageIndex,
            previousPageIndex: previousPageIndex,
            startAtPageTop: true
        )
    }

    private func resumePendingPDFReadAloudIfNeeded() {
        guard currentDocumentKind == .pdf,
              isReadAloudActive,
              !isReadAloudPaused,
              !KittenTTSPlayer.shared.hasActiveReadAloudWork() else {
            return
        }
        let continuation = pendingReadAloudPDFContinuation
        pendingReadAloudPDFContinuation = nil
        switch continuation {
        case .afterBatch(let lastQueuedPage):
            continueReadAloudAfterPDFBatch(lastQueuedPage: lastQueuedPage)
        case .afterCurrentScreen:
            continueReadAloudAfterCurrentPDFScreen()
        case .waitForPage(let expectedPageIndex, let previousPageIndex, let startAtPageTop):
            waitForPDFReadAloudPageChange(
                expectedPageIndex: expectedPageIndex,
                previousPageIndex: previousPageIndex,
                startAtPageTop: startAtPageTop
            )
        case .currentScreen(let startAtPageTop):
            readCurrentPDFPageRemainderAndContinue(startAtPageTop: startAtPageTop)
        case nil:
            readCurrentPDFPageRemainderAndContinue(startAtPageTop: false)
        }
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
        let pageTextCache: [Int: String]
        let segments: [KittenTTSPlayer.ReadAloudSegment]
        let lastPage: PDFPage
    }

    private func pdfReadAloudBatchFromCurrentScreen(startAtPageTop: Bool) -> PDFReadAloudBatch? {
        guard let page = pdfView.currentPage,
              let pageIndex = pdfView.document?.index(for: page),
              pageIndex != NSNotFound else {
            return nil
        }
        let text = startAtPageTop
            ? pdfTextForFullPageReadAloud(page)
            : pdfTextFromVisibleTopToPageEnd(of: page)
        guard let text else { return nil }
        var pages = [page]
        var pageTexts: [PDFReadAloudPageText] = []
        var pageTextCache: [Int: String] = [:]
        pageTextCache[pageIndex] = page.string ?? ""

        if let nextPage = nextPDFPage(after: page),
           let nextPageIndex = pdfView.document?.index(for: nextPage),
           nextPageIndex != NSNotFound,
           let nextText = pdfTextForFullPageReadAloud(nextPage) {
            pages.append(nextPage)
            pageTextCache[nextPageIndex] = nextPage.string ?? ""
            pageTexts.append(PDFReadAloudPageText(pageIndex: pageIndex, text: text))
            pageTexts.append(PDFReadAloudPageText(pageIndex: nextPageIndex, text: nextText))
        } else {
            pageTexts.append(PDFReadAloudPageText(pageIndex: pageIndex, text: text))
        }

        let segments = Self.pdfReadAloudSegments(from: pageTexts)
        guard !segments.isEmpty else { return nil }
        return PDFReadAloudBatch(
            pages: pages,
            pageTextCache: pageTextCache,
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
