import Cocoa
import PDFKit

extension ReaderWindowController {
    @objc func zoomIn() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent + 10)
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8)
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent - 10)
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.scaleFactor * 0.8, 0.1)
        updateZoomLabel()
        saveSession()
    }

    @objc func applyZoomFromField() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            let raw = zoomField.stringValue
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "％", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let percent = Int(raw), percent > 0 else {
                updateZoomLabel()
                return
            }
            setWebZoom(percent)
            return
        }
        let raw = zoomField.stringValue
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(raw), percent > 0 else {
            updateZoomLabel()
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(percent, 10), 800) / 100
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    @objc func applyPageFromField() {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              document.pageCount > 0 else {
            updatePageLabel()
            window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
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
            window?.makeFirstResponder(pdfView)
            return
        }

        let targetIndex = min(max(requestedPage, 1), document.pageCount) - 1
        guard let page = document.page(at: targetIndex) else {
            updatePageLabel()
            window?.makeFirstResponder(pdfView)
            return
        }

        let beforePageIndex = currentPageIndex()
        clearAISelectionForNavigation()
        pdfView.go(to: page)
        lastPageIndex = targetIndex
        scrollPageToTop(page)
        updatePageLabel()
        saveSession()
        recordPageJump(source: "page-field", before: beforePageIndex, after: currentPageIndex(), detail: "requested=\(requestedPage)")
        window?.makeFirstResponder(pdfView)
    }

    @objc func prevPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: -1)
            return
        }
        let beforePageIndex = currentPageIndex()
        pdfView.goToPreviousPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
        recordPageJump(source: "toolbar-prev", before: beforePageIndex, after: currentPageIndex())
    }

    @objc func nextPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: 1)
            return
        }
        let beforePageIndex = currentPageIndex()
        pdfView.goToNextPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
        recordPageJump(source: "toolbar-next", before: beforePageIndex, after: currentPageIndex())
    }

    @objc func togglePDFPageLayout() {
        guard currentDocumentKind == .pdf else { return }
        let nextValue = !isPDFTwoPageModeEnabled()
        setPDFTwoPageModeEnabled(nextValue)
        applyPDFPageLayout(animated: true)
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    func applyPDFPageLayout(animated: Bool) {
        guard currentDocumentKind == .pdf else { return }
        let currentPage = pdfView.currentPage
        let currentPageIndex = currentPage.flatMap { pdfView.document?.index(for: $0) }
        let currentDestination = currentPage.map { PDFDestination(page: $0, at: pdfView.convert(pdfView.bounds.origin, to: $0)) }
        let currentScaleFactor = pdfView.scaleFactor
        let isTwoPage = isPDFTwoPageModeEnabled()
        let targetMode: PDFDisplayMode = isTwoPage ? .twoUp : .singlePage
        let needsDisplayModeChange = pdfView.displayMode != targetMode
        let needsBookModeChange = pdfView.displaysAsBook
        guard needsDisplayModeChange || needsBookModeChange else {
            updatePDFPageLayoutButton()
            return
        }
        pageLayoutButton?.isEnabled = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.08 : 0
            pdfView.autoScales = false
            if needsBookModeChange {
                pdfView.displaysAsBook = false
            }
            if needsDisplayModeChange {
                pdfView.displayMode = targetMode
            }
            pdfView.scaleFactor = currentScaleFactor
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let currentPage,
               let currentPageIndex,
               self.pdfView.document?.index(for: self.pdfView.currentPage ?? PDFPage()) != currentPageIndex {
                let beforeRestoreIndex = self.currentPageIndex()
                self.pdfView.go(to: currentPage)
                self.recordPageJump(source: "layout-switch-restore", before: beforeRestoreIndex, after: self.currentPageIndex())
            }
            if let currentDestination {
                self.pdfView.go(to: currentDestination)
            }
            self.pdfView.scaleFactor = currentScaleFactor
            self.pageLayoutButton?.isEnabled = true
            self.updateZoomLabel()
        }
        updatePDFPageLayoutButton()
    }

    func updatePDFPageLayoutButton() {
        let isTwoPage = isPDFTwoPageModeEnabled()
        pageLayoutButton?.title = isTwoPage
            ? AppText.localized("单页", "Single")
            : AppText.localized("双页", "Two-up")
        pageLayoutButton?.toolTip = isTwoPage
            ? AppText.localized("切换到单页浏览", "Switch to single-page view")
            : AppText.localized("切换到双页浏览", "Switch to two-page view")
    }

    func isPDFTwoPageModeEnabled() -> Bool {
        let defaults = UserDefaults.standard
        let key = pdfTwoPageModeDefaultsKeyForCurrentBook()
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaults.bool(forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func setPDFTwoPageModeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: pdfTwoPageModeDefaultsKeyForCurrentBook())
        defaults.set(enabled, forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func pdfTwoPageModeDefaultsKeyForCurrentBook() -> String {
        guard let currentFileMD5, !currentFileMD5.isEmpty else {
            return Self.pdfTwoPageModeDefaultsKey
        }
        return "\(Self.pdfTwoPageModeDefaultsKey).\(currentFileMD5)"
    }

    func setWebZoom(_ percent: Int) {
        webZoomPercent = min(max(percent, 60), 220)
        zoomField.stringValue = "\(webZoomPercent)%"
        applyWebZoomToPage()
        saveWebProgress()
        window?.makeFirstResponder(webView)
    }

    func applyWebZoomToPage() {
        guard webView != nil else { return }
        webView.pageZoom = 1
        webView.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(webZoomPercent) / 100)');
        """)
    }

    func scrollWebPage(direction: Int) {
        let sign = direction < 0 ? "-" : ""
        webView.evaluateJavaScript("window.scrollBy({top: \(sign)Math.max(240, window.innerHeight * 0.86), behavior: 'smooth'});")
    }

    @objc func goToCover() {
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            webView.evaluateJavaScript("""
            (() => {
              const cover = document.querySelector('section.reader-section[data-leaf-cover="true"]') || document.querySelector('section.reader-section');
              if (cover) {
                cover.scrollIntoView({behavior:'smooth', block:'start'});
              } else {
                window.scrollTo({top:0, behavior:'smooth'});
              }
            })();
            """)
            return
        }
        guard let firstPage = pdfView.document?.page(at: 0) else { return }
        let beforePageIndex = currentPageIndex()
        pdfView.go(to: firstPage)
        scrollPageToTop(firstPage)
        updatePageLabel()
        saveSession()
        recordPageJump(source: "cover", before: beforePageIndex, after: currentPageIndex())
    }


    func turnPageFromScroll(_ direction: EdgePagingPDFView.ScrollPageDirection) {
        guard currentDocumentKind == .pdf else { return }
        clearAISelectionForNavigation()
        let beforePageIndex = currentPageIndex()
        switch direction {
        case .previous:
            pdfView.goToPreviousPage(nil)
        case .next:
            pdfView.goToNextPage(nil)
        }
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
        recordPageJump(source: direction == .previous ? "scroll-previous" : "scroll-next", before: beforePageIndex, after: currentPageIndex())
    }

    func clearAISelectionForNavigation() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        aiPanel.clearSelectedText()

        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
    }

    func clearReaderSelectionForBubbleSelection() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
    }

    func scrollCurrentPageToTop() {
        guard let page = pdfView.currentPage else { return }
        scrollPageToTop(page)
    }

    func scrollPageToTop(_ page: PDFPage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.pdfView.document?.index(for: page) != NSNotFound else {
                return
            }
            let bounds = page.bounds(for: self.pdfView.displayBox)
            let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
            self.pdfView.go(to: destination)
        }
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc func pageChanged() {
        handlePDFPageChange()
    }

    func handlePDFPageChange() {
        markReaderInteraction()
        let newPageIndex = currentPageIndex()
        guard newPageIndex != lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: newPageIndex)
    }

    @objc func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }
        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(selectedText)
        if !selectedText.isEmpty {
            setAIPanelCollapsed(false, animated: true)
        }
    }
}
