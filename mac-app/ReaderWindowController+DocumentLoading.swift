import Cocoa
import PDFKit

private enum ReaderPDFCoverThumbnailLoader {
    static let queue = DispatchQueue(
        label: "com.linlu.leafreader.pdf-cover-thumbnail",
        qos: .utility
    )
}

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
        closeReadingNotePanelsForDocumentTransition()
        webView.stopLoading()
        releaseCurrentOwnedWebResource()
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
        clearPDFSelectionState()
        currentWebSelectedText = ""
        currentWebSelectionRect = nil
        currentDocumentDiagnostics = []
        currentTOCItems = []
        pdfTOCDestinations = [:]
        schedulePDFTOCBuild(for: url, displayBox: pdfView.displayBox)
        storedWordRecords = loadStoredWordRecords()
        storedWebWordRecords.removeAll()
        loadReadingNotesForCurrentDocument()
        aiPanel.loadLinkedWordBubbles(pdfWordRecordStore?.linkedWordBubbles(from: storedWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        applyDocumentDiagnostics([], fileName: url.lastPathComponent)
        scheduleCoverThumbnail(for: url, documentID: currentFileMD5)
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
        applyReaderTheme(refreshDocumentDecorations: false)
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
        let cancellationToken = DocumentLoadCancellationToken()
        activeWebDocumentLoadCancellationToken = cancellationToken
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let document = try WebDocumentLoader.load(url: url, cancellationToken: cancellationToken)
                DispatchQueue.main.async {
                    guard let self, self.documentLoadGeneration == generation else {
                        document.ownedResource?.release()
                        return
                    }
                    self.activeWebDocumentLoadCancellationToken = nil
                    self.applyLoadedWebDocument(document, url: url, kind: kind, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.documentLoadGeneration == generation else { return }
                    self.activeWebDocumentLoadCancellationToken = nil
                    self.showDocumentLoadingFailure(error, generation: generation)
                }
            }
        }
    }

    func applyLoadedWebDocument(_ document: WebReadableDocument, url: URL, kind: ReaderDocumentKind, generation: Int) {
        closeReadingNotePanelsForDocumentTransition()
        webView.stopLoading()
        releaseCurrentOwnedWebResource()
        currentOwnedWebResource = document.ownedResource
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
        clearPDFSelectionState()
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentWebSelectionRect = nil
        pendingWebProgressRestore = nil
        currentDocumentDiagnostics = document.diagnostics
        currentTOCItems = document.tocItems
        pdfTOCDestinations = [:]
        webZoomPercent = 100
        webScrollProgress = 0
        storedWordRecords.removeAll()
        storedWebWordRecords = loadStoredWebWordRecords()
        loadReadingNotesForCurrentDocument()
        aiPanel.loadLinkedWordBubbles(webWordRecordStore?.linkedWordBubbles(from: storedWebWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        aiPanel.setSelectedText("")
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        applyDocumentDiagnostics(document.diagnostics, fileName: url.lastPathComponent)
        if let coverImageURL = document.coverImageURL, let image = NSImage(contentsOf: coverImageURL) {
            image.isTemplate = false
            coverImageView.image = image
            coverImageView.contentTintColor = nil
        } else {
            coverImageView.image = NSImage(
                systemSymbolName: kind == .epub ? "book.closed" : "doc.text",
                accessibilityDescription: AppText.localized("文档封面", "Document cover")
            )
            coverImageView.contentTintColor = ReaderTheme.selected.secondaryTextColor
        }
        coverImageView.isHidden = false
        pageLayoutButton.isHidden = true
        cropButton.isHidden = true
        updateWebProgressLabel(0)
        zoomField.stringValue = "100%"
        if let htmlFileURL = document.htmlFileURL {
            allowedInitialWebNavigationURLs = [htmlFileURL.standardizedFileURL.absoluteString]
            webView.loadFileURL(htmlFileURL, allowingReadAccessTo: document.baseURL)
        } else {
            allowedInitialWebNavigationURLs = [
                document.baseURL.standardizedFileURL.absoluteString,
                "about:blank"
            ]
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

    func releaseCurrentOwnedWebResource() {
        allowedInitialWebNavigationURLs.removeAll()
        currentOwnedWebResource?.release()
        currentOwnedWebResource = nil
    }

    func prepareRuntimeStateForLoadedDocument(url: URL) {
        currentFileURL = url
        currentFileMD5 = fileMD5(for: url)
        pendingPDFTOCBuildRequest = nil
        pendingPDFCoverThumbnailRequest = nil
        sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
        aiConversationStore = currentFileMD5.map { AIConversationStore(fileMD5: $0) }
        loadedAIConversation = nil
        invalidateDocumentAgentIndex()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        storedReadingNotes.removeAll()
        readingNotePanelControllers.removeAll()
        lastPersonalVocabularyPDFPageIndex = nil
        lastPersonalVocabularyWebProgressBucket = nil
        cancelScheduledEmbeddingWarmup()
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil
        highlightedSelectionKeys.removeAll()
        clearAISourceUnderlineTracking()
        clearSearchState()
        originalPDFCropBoxes.removeAll()
    }

    func applyDocumentDiagnostics(_ diagnostics: [String], fileName: String) {
        guard !diagnostics.isEmpty else {
            titleLabel.toolTip = nil
            return
        }
        let summary = diagnostics.prefix(8).joined(separator: "\n")
        titleLabel.toolTip = AppText.localized(
            "部分 EPUB 内容未能读取：\n\(summary)",
            "Some EPUB content could not be read:\n\(summary)"
        )
        NSLog("LeafReader EPUB diagnostics for %@: %@", fileName, diagnostics.joined(separator: " | "))
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

    func scheduleCoverThumbnail(for url: URL, documentID: String?) {
        coverImageView.image = NSImage(
            systemSymbolName: "doc.richtext",
            accessibilityDescription: AppText.localized("文档封面", "Document cover")
        )
        coverImageView.contentTintColor = ReaderTheme.selected.secondaryTextColor
        coverImageView.isHidden = false
        pendingPDFCoverThumbnailRequest = (url, documentID)
    }

    func startPendingPDFCoverThumbnailIfNeeded() {
        guard let request = pendingPDFCoverThumbnailRequest else { return }
        pendingPDFCoverThumbnailRequest = nil
        ReaderPDFCoverThumbnailLoader.queue.async { [weak self] in
            let image = PDFDocument(url: request.url)?.page(at: 0)?.thumbnail(
                of: CGSize(width: 56, height: 76),
                for: .cropBox
            )
            DispatchQueue.main.async {
                guard let self,
                      self.currentDocumentKind == .pdf,
                      self.currentFileMD5 == request.documentID,
                      self.currentFileURL?.standardizedFileURL == request.url.standardizedFileURL,
                      let image else { return }
                image.isTemplate = false
                self.coverImageView.image = image
                self.coverImageView.contentTintColor = nil
            }
        }
    }
}
