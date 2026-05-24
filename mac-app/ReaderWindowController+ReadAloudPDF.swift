import Cocoa
import PDFKit

extension ReaderWindowController {
    func readCurrentPDFPageRemainderAndContinue(startAtPageTop: Bool) {
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

        readAloudPDFPages = batch.pages
        readAloudPDFPageTextCache = batch.pageTextCache
        readAloudPDFCandidatePageIndex = 0
        readAloudPDFSearchLocation = 0

        let segments = readAloudSegmentsWithCurrentLanguageHint(batch.segments)
        SpeechPlaybackCoordinator.shared.speakText(segments: segments) { [weak self] didUseLocalTTS in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleReadAloudStartResult(didUseLocalTTS: didUseLocalTTS)
            }
        } finished: { [weak self] in
            DispatchQueue.main.async {
                self?.continueReadAloudAfterPDFBatch(lastQueuedPage: batch.lastPage)
            }
        }
    }

    func resumePendingPDFReadAloudIfNeeded() {
        guard currentDocumentKind == .pdf,
              isReadAloudActive,
              !isReadAloudPaused,
              !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() else {
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

    private func continueReadAloudAfterPDFBatch(lastQueuedPage: PDFPage) {
        guard isReadAloudActive else { return }
        if readAloudAdvanceMode == .manual {
            pendingReadAloudPDFContinuation = .afterBatch(lastQueuedPage: lastQueuedPage)
            pauseReadAloudForManualAdvance()
            return
        }
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
        continueReadAloudFromPDFPageTop(at: lastQueuedIndex + 1, previousPageIndex: nil)
    }

    private func continueReadAloudAfterCurrentPDFScreen() {
        guard isReadAloudActive else { return }
        if readAloudAdvanceMode == .manual {
            pendingReadAloudPDFContinuation = .afterCurrentScreen
            pauseReadAloudForManualAdvance()
            return
        }
        guard !isReadAloudPaused else {
            pendingReadAloudPDFContinuation = .afterCurrentScreen
            return
        }
        pendingReadAloudPDFContinuation = nil
        guard let before = currentPageIndex() else {
            finishReadAloudFromToolbar()
            return
        }
        continueReadAloudFromPDFPageTop(at: before + 1, previousPageIndex: before)
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
            if preparePDFReadAloudPageTop(page) {
                lastPageIndex = expectedPageIndex
                updatePageLabel()
                saveSession()
            }
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

    func skipReadAloudToNextPDFPage() {
        guard isReadAloudActive,
              let document = pdfView.document,
              let current = readAloudPageLockedAtTopIndex ?? currentPageIndex(),
              current + 1 < document.pageCount else {
            return
        }
        SpeechPlaybackCoordinator.shared.stopSpeaking()
        pendingReadAloudPDFContinuation = nil
        isReadAloudPaused = false
        beginReadAloudLoading()
        continueReadAloudFromPDFPageTop(at: current + 1, previousPageIndex: current)
    }

    private func preparePDFReadAloudPageTop(_ page: PDFPage) -> Bool {
        let pageIndex = pdfView.document?.index(for: page)
        if let pageIndex,
           pageIndex != NSNotFound,
           isPDFPageIndexVisible(pageIndex) {
            lockPDFReadAloudPage(at: pageIndex, save: true)
            return false
        }

        let bounds = page.bounds(for: pdfView.displayBox)
        let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
        pdfView.go(to: destination)
        if let pageIndex, pageIndex != NSNotFound {
            lockPDFReadAloudPage(at: pageIndex, save: false)
        }
        return true
    }

    private func lockPDFReadAloudPage(at pageIndex: Int, save: Bool) {
        readAloudPageLockedAtTopIndex = pageIndex
        guard save else { return }
        lastPageIndex = pageIndex
        updatePageLabel()
        saveSession()
    }

    func continueReadAloudFromPDFPageTop(at pageIndex: Int, previousPageIndex: Int?) {
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else {
            finishReadAloudFromToolbar()
            return
        }
        if preparePDFReadAloudPageTop(page) {
            waitForPDFReadAloudPageChange(
                expectedPageIndex: pageIndex,
                previousPageIndex: previousPageIndex,
                startAtPageTop: true
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isReadAloudActive else { return }
                guard !self.isReadAloudPaused else {
                    self.pendingReadAloudPDFContinuation = .currentScreen(startAtPageTop: true)
                    return
                }
                self.readCurrentPDFPageRemainderAndContinue(startAtPageTop: true)
            }
        }
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
        let segments: [SpeechPlaybackCoordinator.ReadAloudSegment]
        let lastPage: PDFPage
    }

    private func pdfReadAloudBatchFromCurrentScreen(startAtPageTop: Bool) -> PDFReadAloudBatch? {
        guard let page = pdfReadAloudStartPageForCurrentScreen(),
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

    func pdfReadAloudStartPageForCurrentScreen() -> PDFPage? {
        if let lockedPageIndex = readAloudPageLockedAtTopIndex,
           let document = pdfView.document,
           lockedPageIndex >= 0,
           lockedPageIndex < document.pageCount,
           isPDFPageIndexVisible(lockedPageIndex) {
            return document.page(at: lockedPageIndex)
        }

        guard pdfView.displayMode == .twoUp,
              let document = pdfView.document else {
            return pdfView.currentPage
        }
        let visiblePages = pdfView.visiblePages
            .filter { document.index(for: $0) != NSNotFound }
            .sorted { document.index(for: $0) < document.index(for: $1) }
        return visiblePages.first ?? pdfView.currentPage
    }

    func isPDFPageIndexVisible(_ pageIndex: Int) -> Bool {
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount else {
            return false
        }
        return pdfView.visiblePages.contains { document.index(for: $0) == pageIndex }
    }

    func pdfReadAloudLanguageProbeText(pageLimit: Int) -> String? {
        guard pageLimit > 0,
              let document = pdfView.document,
              let startPage = pdfReadAloudStartPageForCurrentScreen() else {
            return pdfView.currentPage?.string
        }
        let startIndex = document.index(for: startPage)
        guard startIndex != NSNotFound else { return pdfView.currentPage?.string }
        let endIndex = min(document.pageCount, startIndex + pageLimit)
        let text = (startIndex..<endIndex)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private struct PDFReadAloudPageText {
        let pageIndex: Int
        let text: String
    }

    private static func pdfReadAloudSegments(from pageTexts: [PDFReadAloudPageText]) -> [SpeechPlaybackCoordinator.ReadAloudSegment] {
        var segments: [SpeechPlaybackCoordinator.ReadAloudSegment] = []
        for pageText in pageTexts {
            let text = pageText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for sourceSegment in SpeechTextPolicy.segments(for: text) {
                let speechText = SpeechTextPolicy.normalizedReadAloudInput(sourceSegment)
                guard !speechText.isEmpty else { continue }
                segments.append(SpeechPlaybackCoordinator.ReadAloudSegment(
                    speechText: speechText,
                    displayText: speechText,
                    matchText: sourceSegment,
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
}
