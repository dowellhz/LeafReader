import Foundation

extension ReaderWindowController {
    @objc func applyPageFromField() {
        guard currentDocumentKind == .pdf,
              let backend = activePagedReaderBackend,
              backend.pageCount > 0 else {
            updatePageLabel()
            activeReaderBackend?.focus()
            return
        }

        let raw = pageLabel.stringValue
        let pageNumberText: String
        if let range = raw.range(of: #"\d+"#, options: .regularExpression) {
            pageNumberText = String(raw[range])
        } else {
            pageNumberText = ""
        }
        guard let requestedPage = Int(pageNumberText) else {
            updatePageLabel()
            backend.focus()
            return
        }

        let targetIndex = min(max(requestedPage, 1), backend.pageCount) - 1
        guard backend.navigate(toPage: targetIndex, placement: .top) else {
            updatePageLabel()
            backend.focus()
            return
        }

        clearAISelectionForNavigation()
        lastPageIndex = targetIndex
        updatePageLabel()
        saveSession()
        backend.focus()
    }

    @objc func prevPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: -1)
            return
        }
        turnPDFPage(
            direction: .previous,
            targetPlacement: PDFPagingPolicy.previousPagePlacement(for: currentPDFReadingMode())
        )
    }

    @objc func nextPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: 1)
            return
        }
        turnPDFPage(direction: .next, targetPlacement: .top)
    }

    func scrollWebPage(direction: Int) {
        activeContinuousReaderBackend?.scrollByPage(direction < 0 ? .previous : .next)
    }

    @objc func goToCover() {
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            activeContinuousReaderBackend?.scrollToCover()
            return
        }
        guard activePagedReaderBackend?.navigate(toPage: 0, placement: .top) == true else { return }
        updatePageLabel()
        saveSession()
    }

    @objc func goToFarthestReadingPosition() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            let storedProgress = sessionStore.loadFarthestWebProgress()
            if let zoomPercent = storedProgress?.zoomPercent {
                webZoomPercent = zoomPercent
                zoomField.stringValue = "\(webZoomPercent)%"
                applyWebZoomToPage()
            }
            jumpToWebProgress(storedProgress?.scrollProgress ?? webScrollProgress, animated: true)
            return
        }
        guard let backend = activePagedReaderBackend, backend.pageCount > 0 else { return }
        let storedProgress = sessionStore.loadFarthestPDFProgress()
        let targetIndex = min(max(storedProgress?.pageIndex ?? backend.currentPageIndex ?? 0, 0), backend.pageCount - 1)
        lastPageIndex = targetIndex
        if let storedProgress, ReaderSessionPolicy.isRestorablePDFScale(storedProgress.scale) {
            applyReadablePDFScale(storedProgress.scale)
        }
        if let anchorPoint = storedProgress?.anchorPoint {
            guard backend.restoreViewportAnchor(
                ReaderPagedViewportAnchor(pageIndex: targetIndex, point: anchorPoint)
            ) else { return }
        } else {
            guard backend.navigate(toPage: targetIndex, placement: .top) else { return }
        }
        updatePageLabel()
        saveSession()
        backend.focus()
    }

    func jumpToWebProgress(_ progressValue: Double, animated: Bool) {
        let progress = min(1, max(0, progressValue))
        webScrollProgress = progress
        updateWebProgressLabel(progress)
        scrollWebToProgress(progress, animated: animated)
        saveSession()
        activeContinuousReaderBackend?.focus()
    }

    func scrollWebToProgress(_ progress: Double, animated: Bool) {
        activeContinuousReaderBackend?.scroll(toProgress: progress, animated: animated)
    }


    func turnPageFromScroll(_ direction: EdgePagingPDFView.ScrollPageDirection) {
        guard currentDocumentKind == .pdf else { return }
        clearAISelectionForNavigation()
        turnPDFPage(
            direction: direction,
            targetPlacement: direction == .previous
                ? PDFPagingPolicy.previousPagePlacement(for: currentPDFReadingMode())
                : .top
        )
    }

    private func turnPDFPage(
        direction: EdgePagingPDFView.ScrollPageDirection,
        targetPlacement: PDFPageNavigationPlacement
    ) {
        guard let backend = activePagedReaderBackend, backend.pageCount > 0 else { return }
        let readingMode = currentPDFReadingMode()
        let currentIndex = PDFPagingPolicy.navigationPageIndex(
            readingMode: readingMode,
            viewportPageIndex: backend.viewportAnchor?.pageIndex,
            currentPageIndex: backend.currentPageIndex
        ) ?? 0
        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = currentIndex - 1
        case .next:
            targetIndex = currentIndex + 1
        }
        guard targetIndex >= 0,
              targetIndex < backend.pageCount,
              backend.navigate(
                toPage: targetIndex,
                placement: targetPlacement == .top ? .top : .bottom
              ) else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = targetIndex
        updatePageLabel()
        saveSession()
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc func pageChanged() {
        handlePDFPageChange()
    }

    func handlePDFPageChange() {
        markReaderInteraction()
        hideSelectionToolbar()
        materializeStoredWordAnnotationsForVisiblePages()
        let newPageIndex = currentPageIndex()
        guard newPageIndex != lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
        if !isReadAloudActive {
            scheduleDocumentEmbeddingWarmup(priorityPageIndex: newPageIndex)
        }
    }

}
