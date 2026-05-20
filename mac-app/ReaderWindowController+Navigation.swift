import PDFKit

extension ReaderWindowController {
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
        guard let document = pdfView.document, document.pageCount > 0 else { return }
        let storedProgress = sessionStore.loadFarthestPDFProgress()
        let targetIndex = min(max(storedProgress?.pageIndex ?? currentPageIndex() ?? 0, 0), document.pageCount - 1)
        guard let page = document.page(at: targetIndex) else { return }
        let beforePageIndex = currentPageIndex()
        pdfView.go(to: page)
        lastPageIndex = targetIndex
        if let storedProgress, ReaderSessionPolicy.isRestorablePDFScale(storedProgress.scale) {
            applyReadablePDFScale(storedProgress.scale)
        }
        if let anchorPoint = storedProgress?.anchorPoint {
            restorePDFViewportAnchor(page: page, point: anchorPoint)
        } else {
            scrollPageToTop(page)
        }
        updatePageLabel()
        saveSession()
        recordPageJump(source: "farthest-position", before: beforePageIndex, after: currentPageIndex(), detail: "target=\(targetIndex + 1)")
        window?.makeFirstResponder(pdfView)
    }

    func jumpToWebProgress(_ progressValue: Double, animated: Bool) {
        let progress = min(1, max(0, progressValue))
        webScrollProgress = progress
        updateWebProgressLabel(progress)
        scrollWebToProgress(progress, animated: animated)
        saveSession()
        window?.makeFirstResponder(webView)
    }

    func scrollWebToProgress(_ progress: Double, animated: Bool) {
        let behavior = animated ? "smooth" : "auto"
        let script = """
        (() => {
          const progress = \(progress);
          const scroll = () => {
            const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            window.scrollTo({ top: scrollHeight * progress, behavior: '\(behavior)' });
          };
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => requestAnimationFrame(scroll), { once: true });
          } else {
            requestAnimationFrame(() => requestAnimationFrame(scroll));
          }
        })();
        """
        webView.evaluateJavaScript(script)
    }


    func turnPageFromScroll(_ direction: EdgePagingPDFView.ScrollPageDirection) {
        guard currentDocumentKind == .pdf else { return }
        clearAISelectionForNavigation()
        let beforePageIndex = currentPageIndex()
        switch direction {
        case .previous:
            pdfView.goToPreviousPage(nil)
            scrollCurrentPageToBottom()
        case .next:
            pdfView.goToNextPage(nil)
            scrollCurrentPageToTop()
        }
        updatePageLabel()
        saveSession()
        recordPageJump(source: direction == .previous ? "scroll-previous" : "scroll-next", before: beforePageIndex, after: currentPageIndex())
    }

    func scrollCurrentPageToTop() {
        guard let page = pdfView.currentPage else { return }
        scrollPageToTop(page)
    }

    func scrollCurrentPageToBottom() {
        guard let page = pdfView.currentPage else { return }
        scrollPageToBottom(page)
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

    func scrollPageToBottom(_ page: PDFPage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.pdfView.document?.index(for: page) != NSNotFound else {
                return
            }
            let bounds = page.bounds(for: self.pdfView.displayBox)
            let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.minY))
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
        hideSelectionToolbar()
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

}
