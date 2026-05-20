import Cocoa
import CryptoKit
import PDFKit

extension ReaderWindowController {
    func pdfViewWillChangeScaleFactor(_ sender: PDFView) {
        updateZoomLabel()
        DispatchQueue.main.async { [weak self] in
            self?.updateZoomLabel()
            self?.saveSession()
        }
    }

    func pdfViewPageChanged(_ sender: PDFView) {
        handlePDFPageChange()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = true
        } else if obj.object as? NSTextField === pageLabel {
            isEditingPageField = true
            if currentDocumentKind == .pdf, let pageIndex = currentPageIndex() {
                pageLabel.stringValue = "\(pageIndex + 1)"
                updatePageLabelTextColor()
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = false
            updateZoomLabel()
        } else if obj.object as? NSTextField === pageLabel {
            isEditingPageField = false
            updatePageLabel()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === zoomField, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyZoomFromField()
            return true
        }
        if control === pageLabel, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyPageFromField()
            return true
        }
        return false
    }

    func updateZoomLabel() {
        if isEditingZoomField { return }
        guard currentDocumentKind == .pdf else {
            zoomField.stringValue = "\(webZoomPercent)%"
            return
        }
        zoomField.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    func updatePageLabel() {
        if isEditingPageField { return }
        guard currentDocumentKind == .pdf else {
            if pageLabel.stringValue == AppText.noPDF || pageLabel.stringValue == "EPUB" || pageLabel.stringValue == "DOCX" {
                pageLabel.stringValue = "0%"
                updatePageLabelTextColor()
            }
            return
        }
        guard let document = pdfView.document else {
            pageLabel.stringValue = AppText.noPDF
            updatePageLabelTextColor()
            return
        }
        guard let page = pdfView.currentPage else {
            pageLabel.stringValue = "1  /  \(document.pageCount)"
            updatePageLabelTextColor()
            return
        }
        pageLabel.stringValue = "\(document.index(for: page) + 1)  /  \(document.pageCount)"
        updatePageLabelTextColor()
    }

    func currentPageIndex() -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page)
    }


    func jumpToDocumentSource(index: Int) {
        setAIPanelCollapsed(false, animated: true)
        if currentDocumentKind == .pdf {
            jumpToPDFPage(index: index, skipIfCurrentPage: true)
            return
        }
        jumpToWebDocumentSection(index: index)
    }

    func jumpToPDFPage(index: Int, skipIfCurrentPage: Bool = false) {
        guard let page = pdfView.document?.page(at: index) else { return }
        setAIPanelCollapsed(false, animated: true)
        if skipIfCurrentPage, currentPageIndex() == index {
            updatePageLabel()
            return
        }
        let beforePageIndex = currentPageIndex()
        let bounds = page.bounds(for: pdfView.displayBox)
        pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY)))
        lastPageIndex = index
        updatePageLabel()
        saveSession()
        recordPageJump(source: "document-source", before: beforePageIndex, after: currentPageIndex(), detail: "target=\(index + 1)")
    }

    func jumpToWebDocumentSection(index: Int) {
        ensureDocumentAgentIndex()
        let count = max(1, pdfAgentIndex?.locationCount ?? 1)
        let progress = count <= 1 ? 0 : Double(min(max(index, 0), count - 1)) / Double(count - 1)
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
        updatePageLabelTextColor()
        let script = """
        (() => {
          const progress = \(progress);
          const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          window.scrollTo({ top: scrollHeight * progress, behavior: 'smooth' });
        })();
        """
        webView.evaluateJavaScript(script)
        saveWebProgress()
    }


    func fileMD5(for url: URL) -> String? {
        let fastID = DocumentIdentity.fastID(for: url)
        let legacyMD5 = cachedLegacyMD5(for: url)
        return DocumentIdentity.selectedID(
            fastID: fastID,
            legacyID: legacyMD5,
            legacyHasData: legacyMD5.map { hasStoredDocumentData(documentID: $0) } ?? false,
            fastHasData: hasStoredDocumentData(documentID: fastID)
        )
    }

    func fastDocumentID(for url: URL) -> String {
        DocumentIdentity.fastID(for: url)
    }

    func cachedLegacyMD5(for url: URL) -> String? {
        let defaults = UserDefaults.standard
        let cache = defaults.dictionary(forKey: Self.fileMD5CacheDefaultsKey) as? [String: String] ?? [:]
        return cache[DocumentIdentity.legacyCacheKey(for: url)]
    }

    func hasStoredDocumentData(documentID: String) -> Bool {
        let defaults = UserDefaults.standard
        for suffix in ["pageIndex", "scale", "webProgress", "webZoom", "wordRecords", "webWordRecords"] {
            if defaults.object(forKey: "bookSession.\(documentID).\(suffix)") != nil {
                return true
            }
        }
        if defaults.object(forKey: "aiConversation.\(documentID)") != nil {
            return true
        }
        if !WordRecordSQLiteStore.shared.loadPDFRecords(documentID: documentID).isEmpty {
            return true
        }
        if !WordRecordSQLiteStore.shared.loadWebRecords(documentID: documentID).isEmpty {
            return true
        }
        return false
    }

    func restoreWebProgressAfterLoad() {
        guard currentDocumentKind != .pdf,
              let progress = sessionStore.loadWebProgress() else {
            return
        }
        let scrollProgress = progress.scrollProgress
        webScrollProgress = scrollProgress
        pageLabel.stringValue = "\(Int(round(scrollProgress * 100)))%"
        updatePageLabelTextColor()
        if let percent = progress.zoomPercent {
            webZoomPercent = percent
            zoomField.stringValue = "\(webZoomPercent)%"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ReaderSessionPolicy.webRestoreDelay) { [weak self] in
            guard let self, self.currentDocumentKind != .pdf else { return }
            self.applyWebZoomToPage()
            self.zoomField.stringValue = "\(self.webZoomPercent)%"
            self.webView.evaluateJavaScript("""
            (() => {
              const height = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
              window.scrollTo(0, height * \(scrollProgress));
            })();
            """)
        }
    }

    func saveWebProgress() {
        guard !isRestoringSession, currentDocumentKind != .pdf else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWebProgressSave) > ReaderSessionPolicy.webProgressSaveInterval else { return }
        lastWebProgressSave = now
        sessionStore.saveWebProgress(scrollProgress: webScrollProgress, zoomPercent: webZoomPercent)
    }

    func restoreBookProgressOrGoHome() {
        guard let document = pdfView.document else { return }
        guard let progress = sessionStore.loadPDFProgress() else {
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
            }
            applyReadablePDFScale()
            reapplyPDFZoomModeIfNeeded()
            return
        }

        let pageIndex = progress.pageIndex
        let beforePageIndex = currentPageIndex()
        var restoredPage: PDFPage?
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            restoredPage = page
            pdfView.go(to: page)
            recordPageJump(source: "session-restore", before: beforePageIndex, after: currentPageIndex(), detail: "target=\(pageIndex + 1)")
        } else if let firstPage = document.page(at: 0) {
            restoredPage = firstPage
            pdfView.go(to: firstPage)
            recordPageJump(source: "home", before: beforePageIndex, after: currentPageIndex())
        }

        let scale = progress.scale
        if ReaderSessionPolicy.isRestorablePDFScale(scale) {
            applyReadablePDFScale(scale)
        }
        if let restoredPage, let anchorPoint = progress.anchorPoint {
            restorePDFViewportAnchor(page: restoredPage, point: anchorPoint)
        }
        reapplyPDFZoomModeIfNeeded()
    }

    func applyReadablePDFScale(_ scale: CGFloat = ReaderWindowController.minimumReadablePDFScale) {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(scale, Self.minimumReadablePDFScale), 8)
        updateZoomLabel()
    }

    func saveSession() {
        if isRestoringSession { return }
        sessionSaveTask.schedule { [weak self] in
            self?.performSessionSave()
        }
    }

    func performSessionSave() {
        sessionSaveTask.cancel()
        guard let url = currentFileURL else { return }
        sessionStore.saveLastDocumentURL(url)
        guard currentDocumentKind == .pdf else {
            saveWebProgress()
            RecentDocumentsStore.updateProgress(url: url, kind: currentDocumentKind, progress: webScrollProgress)
            return
        }
        let anchor = currentPDFViewportAnchor()
        let pageIndex = anchor?.pageIndex ?? pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        sessionStore.savePDFProgress(pageIndex: pageIndex, scale: pdfView.scaleFactor, anchorPoint: anchor?.point)
        let pageCount = max(1, pdfView.document?.pageCount ?? 1)
        RecentDocumentsStore.updateProgress(
            url: url,
            kind: currentDocumentKind,
            progress: Double(pageIndex + 1) / Double(pageCount)
        )
    }

    func currentPDFViewportAnchor() -> (pageIndex: Int, point: CGPoint)? {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              document.pageCount > 0 else {
            return nil
        }
        let anchorInView = NSPoint(
            x: pdfView.bounds.midX,
            y: max(pdfView.bounds.minY, pdfView.bounds.maxY - ReaderSessionPolicy.pdfViewportAnchorTopInset)
        )
        let page = pdfView.page(for: anchorInView, nearest: true) ?? pdfView.currentPage
        guard let page else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let point = pdfView.convert(anchorInView, to: page)
        return (pageIndex, point)
    }

    func restorePDFViewportAnchor(page: PDFPage, point: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.currentDocumentKind == .pdf,
                  self.pdfView.document?.index(for: page) != NSNotFound else {
                return
            }
            self.pdfView.go(to: PDFDestination(page: page, at: point))
            self.updatePageLabel()
        }
    }

    func restoreSession() {
        guard let url = sessionStore.restoreLastDocumentURL() else { return }

        isRestoringSession = true
        loadDocument(url)
        isRestoringSession = false
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    func scheduleSessionRestoreAfterInitialPaint() {
        DispatchQueue.main.asyncAfter(deadline: .now() + ReaderSessionPolicy.initialRestoreDelay) { [weak self] in
            guard let self, self.currentFileURL == nil else { return }
            self.restoreSession()
        }
    }
}
