import PDFKit

extension ReaderWindowController {
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
}
