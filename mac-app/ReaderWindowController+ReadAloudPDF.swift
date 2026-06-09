import Cocoa
import PDFKit

extension ReaderWindowController {
    private var pdfReadAloudBatchBuilder: PDFReadAloudBatchBuilder {
        PDFReadAloudBatchBuilder(
            pdfView: pdfView,
            chromeFilterState: readAloudState.pdfChromeFilter
        ) { [weak self] in
            self?.titleLabel.stringValue ?? ""
        }
    }

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

    func speakPDFSelectionFromToolbar(text: String) -> Bool {
        guard currentDocumentKind == .pdf,
              canStartReadAloudWithLocalTTS(),
              let selection = pdfView.currentSelection,
              let document = pdfView.document,
              let firstPage = selection.pages.first else {
            return false
        }
        let selectedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return false }
        let firstPageIndex = document.index(for: firstPage)
        guard firstPageIndex != NSNotFound else { return false }

        let pages = selection.pages
        var pageTextCache: [Int: String] = [:]
        for page in pages {
            let index = document.index(for: page)
            guard index != NSNotFound else { continue }
            pageTextCache[index] = page.string ?? ""
        }

        readAloudPDFPages = pages
        readAloudPDFPageTextCache = pageTextCache
        readAloudPDFCandidatePageIndex = 0
        readAloudPDFSearchLocation = 0

        let speechText = SpeechTextPolicy.normalizedReadAloudInput(selectedText)
        guard !speechText.isEmpty else { return false }
        beginReadAloudLoading()
        let matchRange = ReadAloudTextMatcher.range(
            of: selectedText,
            in: pageTextCache[firstPageIndex] ?? "",
            allowsPartialFallback: false
        )
        let segment = SpeechPlaybackCoordinator.ReadAloudSegment(
            speechText: speechText,
            displayText: speechText,
            matchText: selectedText,
            matchRange: matchRange,
            pageIndex: firstPageIndex,
            speechLanguageHint: readAloudSpeechLanguageHint
        )
        SpeechPlaybackCoordinator.shared.speakText(segments: [segment]) { [weak self] didUseLocalTTS in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleReadAloudStartResult(didUseLocalTTS: didUseLocalTTS)
            }
        } finished: { [weak self] in
            DispatchQueue.main.async {
                self?.finishReadAloudFromToolbar()
            }
        }
        return true
    }

    func resumePendingPDFReadAloudIfNeeded(trigger: ReadAloudContinuationTrigger = .automatic) {
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
            continueReadAloudAfterPDFBatch(lastQueuedPage: lastQueuedPage, trigger: trigger)
        case .afterCurrentScreen:
            continueReadAloudAfterCurrentPDFScreen(trigger: trigger)
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

    private func continueReadAloudAfterPDFBatch(
        lastQueuedPage: PDFPage,
        trigger: ReadAloudContinuationTrigger = .automatic
    ) {
        guard isReadAloudActive else { return }
        if deferReadAloudContinuationIfNeeded(trigger: trigger, setPending: {
            pendingReadAloudPDFContinuation = .afterBatch(lastQueuedPage: lastQueuedPage)
        }) {
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

    private func continueReadAloudAfterCurrentPDFScreen(
        trigger: ReadAloudContinuationTrigger = .automatic
    ) {
        guard isReadAloudActive else { return }
        if deferReadAloudContinuationIfNeeded(trigger: trigger, setPending: {
            pendingReadAloudPDFContinuation = .afterCurrentScreen
        }) {
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
        readAloudState.resumePlayback()
        beginReadAloudLoading()
        continueReadAloudFromPDFPageTop(at: current + 1, previousPageIndex: current)
    }

    private func preparePDFReadAloudPageTop(_ page: PDFPage) -> Bool {
        let pageIndex = pdfView.document?.index(for: page)
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

    private func pdfReadAloudBatchFromCurrentScreen(startAtPageTop: Bool) -> PDFReadAloudBatchBuilder.Batch? {
        pdfReadAloudBatchBuilder.batchFromCurrentScreen(
            startAtPageTop: startAtPageTop,
            lockedPageIndex: readAloudPageLockedAtTopIndex
        )
    }

    func pdfReadAloudLanguageProbeText(pageLimit: Int) -> String? {
        pdfReadAloudBatchBuilder.languageProbeText(
            pageLimit: pageLimit,
            lockedPageIndex: readAloudPageLockedAtTopIndex
        )
    }
}
