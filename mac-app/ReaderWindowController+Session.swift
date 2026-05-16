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
            }
            return
        }
        guard let document = pdfView.document else {
            pageLabel.stringValue = AppText.noPDF
            return
        }
        guard let page = pdfView.currentPage else {
            pageLabel.stringValue = "1  /  \(document.pageCount)"
            return
        }
        pageLabel.stringValue = "\(document.index(for: page) + 1)  /  \(document.pageCount)"
    }

    func currentPageIndex() -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page)
    }


    func jumpToDocumentSource(index: Int) {
        setAIPanelCollapsed(false, animated: true)
        if currentDocumentKind == .pdf {
            jumpToPDFPage(index: index)
            return
        }
        jumpToWebDocumentSection(index: index)
    }

    func jumpToPDFPage(index: Int) {
        guard let page = pdfView.document?.page(at: index) else { return }
        setAIPanelCollapsed(false, animated: true)
        let bounds = page.bounds(for: pdfView.displayBox)
        pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY)))
        lastPageIndex = index
        updatePageLabel()
        saveSession()
    }

    func jumpToWebDocumentSection(index: Int) {
        ensureDocumentAgentIndex()
        let count = max(1, pdfAgentIndex?.locationCount ?? 1)
        let progress = count <= 1 ? 0 : Double(min(max(index, 0), count - 1)) / Double(count - 1)
        webScrollProgress = progress
        pageLabel.stringValue = "\(Int(round(progress * 100)))%"
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
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(url.standardizedFileURL.path)|\(fileSize)|\(modifiedAt)"
        let defaults = UserDefaults.standard
        var cache = defaults.dictionary(forKey: Self.fileMD5CacheDefaultsKey) as? [String: String] ?? [:]
        if let cached = cache[cacheKey] {
            return cached
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        let md5 = digest.map { String(format: "%02x", $0) }.joined()
        cache[cacheKey] = md5
        if cache.count > 80 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(80))
        }
        defaults.set(cache, forKey: Self.fileMD5CacheDefaultsKey)
        return md5
    }

    func restoreWebProgressAfterLoad() {
        guard currentDocumentKind != .pdf,
              let progress = sessionStore.loadWebProgress() else {
            return
        }
        let scrollProgress = progress.scrollProgress
        webScrollProgress = scrollProgress
        pageLabel.stringValue = "\(Int(round(scrollProgress * 100)))%"
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
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        } else if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
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
        pendingSessionSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSessionSave()
        }
        pendingSessionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func performSessionSave() {
        pendingSessionSaveWorkItem = nil
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
