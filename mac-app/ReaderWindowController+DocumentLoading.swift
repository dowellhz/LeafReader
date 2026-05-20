import Cocoa
import PDFKit

extension ReaderWindowController {
    func loadPDF(_ url: URL, generation: Int? = nil) {
        guard let document = PDFDocument(url: url) else {
            if let generation {
                showDocumentLoadingFailure(
                    NSError(domain: "LeafReader", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: AppText.localized("无法打开 PDF。", "Unable to open PDF.")
                    ]),
                    generation: generation
                )
            }
            return
        }
        currentDocumentKind = .pdf
        pdfView.isHidden = false
        webView.isHidden = true
        pdfView.document = document
        prepareRuntimeStateForLoadedDocument(url: url)
        captureOriginalPDFCropBoxes()
        applyPDFMarginCropIfNeeded()
        pdfWordRecordStore = currentFileMD5.map { PDFWordRecordStore(fileMD5: $0) }
        webWordRecordStore = nil
        currentWebPlainText = ""
        webPlainTextGeneration += 1
        currentWebSelectedText = ""
        currentWebSelectionRect = nil
        currentTOCItems = []
        pdfTOCDestinations = [:]
        schedulePDFTOCBuild(for: url, displayBox: pdfView.displayBox)
        storedWordRecords = loadStoredWordRecords()
        storedWebWordRecords.removeAll()
        restoreStoredWordAnnotations()
        aiPanel.loadLinkedWordBubbles(pdfWordRecordStore?.linkedWordBubbles(from: storedWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        updateCoverThumbnail(from: document)
        pageLayoutButton.isHidden = false
        cropButton.isHidden = false
        updatePDFMarginCropButton()
        applyPDFPageLayout(animated: false)

        if !didRegisterSelectionObserver {
            didRegisterSelectionObserver = true
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        }

        restoreBookProgressOrGoHome()
        lastPageIndex = currentPageIndex()
        applyReaderTheme()
        updatePageLabel()
        updateZoomLabel()
        RecentDocumentsStore.record(url: url, kind: .pdf)
        saveSession()
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
        if let generation {
            finishDocumentLoadingAfterAIBubbles(generation: generation)
        }
    }

    func loadWebDocument(_ url: URL, kind: ReaderDocumentKind, generation: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let document = try WebDocumentLoader.load(url: url)
                DispatchQueue.main.async {
                    guard let self, self.documentLoadGeneration == generation else { return }
                    self.applyLoadedWebDocument(document, url: url, kind: kind, generation: generation)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showDocumentLoadingFailure(error, generation: generation)
                }
            }
        }
    }

    func applyLoadedWebDocument(_ document: WebReadableDocument, url: URL, kind: ReaderDocumentKind, generation: Int) {
        currentDocumentKind = kind
        pdfView.isHidden = true
        pdfDimOverlay.isHidden = true
        webView.isHidden = false
        pdfView.document = nil
        prepareRuntimeStateForLoadedDocument(url: url)
        pdfWordRecordStore = nil
        webWordRecordStore = currentFileMD5.map { WebWordRecordStore(fileMD5: $0) }
        currentWebPlainText = document.plainText
        webPlainTextGeneration += 1
        let webPlainTextGeneration = webPlainTextGeneration
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentWebSelectionRect = nil
        currentTOCItems = document.tocItems
        pdfTOCDestinations = [:]
        webZoomPercent = 100
        webScrollProgress = 0
        storedWordRecords.removeAll()
        storedWebWordRecords = loadStoredWebWordRecords()
        aiPanel.loadLinkedWordBubbles(webWordRecordStore?.linkedWordBubbles(from: storedWebWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        aiPanel.setSelectedText("")
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        if let coverImageURL = document.coverImageURL, let image = NSImage(contentsOf: coverImageURL) {
            coverImageView.image = image
        } else {
            coverImageView.image = NSImage(systemSymbolName: kind == .epub ? "book.closed" : "doc.text", accessibilityDescription: nil)
        }
        coverImageView.isHidden = false
        pageLayoutButton.isHidden = true
        cropButton.isHidden = true
        updateWebProgressLabel(0)
        zoomField.stringValue = "100%"
        if let htmlFileURL = document.htmlFileURL {
            webView.loadFileURL(htmlFileURL, allowingReadAccessTo: document.baseURL)
        } else {
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
        }
        applyReaderTheme()
        applyWebZoomToPage()
        restoreWebProgressAfterLoad()
        RecentDocumentsStore.record(url: url, kind: kind)
        saveSession()
        scheduleWebPlainTextLoad(document.plainTextLoader, generation: webPlainTextGeneration)
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
        finishDocumentLoadingAfterAIBubbles(generation: generation)
    }

    func prepareRuntimeStateForLoadedDocument(url: URL) {
        currentFileURL = url
        currentFileMD5 = fileMD5(for: url)
        sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
        aiConversationStore = currentFileMD5.map { AIConversationStore(fileMD5: $0) }
        loadedAIConversation = nil
        invalidateDocumentAgentIndex()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        cancelScheduledEmbeddingWarmup()
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil
        highlightedSelectionKeys.removeAll()
        clearAISourceUnderlineTracking()
        clearSearchState()
        originalPDFCropBoxes.removeAll()
    }

    func scheduleWebPlainTextLoad(_ loader: (() -> String)?, generation: Int) {
        guard let loader else { return }
        let documentID = currentFileMD5
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let plainText = loader()
            DispatchQueue.main.async {
                guard let self,
                      self.webPlainTextGeneration == generation,
                      self.currentFileMD5 == documentID else {
                    return
                }
                self.currentWebPlainText = plainText
                self.invalidateDocumentAgentIndex()
                self.scheduleDocumentEmbeddingWarmup(priorityPageIndex: self.currentEmbeddingPriorityIndex())
            }
        }
    }

    func updateCoverThumbnail(from document: PDFDocument) {
        guard let firstPage = document.page(at: 0) else {
            coverImageView.image = nil
            coverImageView.isHidden = true
            return
        }

        coverImageView.image = firstPage.thumbnail(of: CGSize(width: 56, height: 76), for: .cropBox)
        coverImageView.isHidden = false
    }
}
