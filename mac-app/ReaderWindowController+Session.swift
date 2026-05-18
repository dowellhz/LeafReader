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
        let fastID = fastDocumentID(for: url)
        guard let legacyMD5 = cachedLegacyMD5(for: url), legacyMD5 != fastID else {
            return fastID
        }

        if hasStoredDocumentData(documentID: legacyMD5), !hasStoredDocumentData(documentID: fastID) {
            return legacyMD5
        }
        return fastID
    }

    func fastDocumentID(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let identity = "\(url.standardizedFileURL.path)|\(fileSize)|\(modifiedAt)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "fast-\(digest)"
    }

    func cachedLegacyMD5(for url: URL) -> String? {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.standardizedFileURL.path)|\(fileSize)|\(modifiedAt)"
        let defaults = UserDefaults.standard
        let cache = defaults.dictionary(forKey: Self.fileMD5CacheDefaultsKey) as? [String: String] ?? [:]
        return cache[cacheKey]
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
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
        guard now.timeIntervalSince(lastWebProgressSave) > 0.5 else { return }
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
            return
        }

        let pageIndex = progress.pageIndex
        let beforePageIndex = currentPageIndex()
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
            recordPageJump(source: "session-restore", before: beforePageIndex, after: currentPageIndex(), detail: "target=\(pageIndex + 1)")
        } else if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
            recordPageJump(source: "home", before: beforePageIndex, after: currentPageIndex())
        }

        let scale = progress.scale
        if scale >= 0.1, scale <= 8 {
            applyReadablePDFScale(scale)
        }
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
        let pageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        sessionStore.savePDFProgress(pageIndex: pageIndex, scale: pdfView.scaleFactor)
        let pageCount = max(1, pdfView.document?.pageCount ?? 1)
        RecentDocumentsStore.updateProgress(
            url: url,
            kind: currentDocumentKind,
            progress: Double(pageIndex + 1) / Double(pageCount)
        )
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.currentFileURL == nil else { return }
            self.restoreSession()
        }
    }
}
