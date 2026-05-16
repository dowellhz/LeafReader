import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

extension ReaderWindowController {
    @objc func openPDF() {
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadDocument(url)
        }
    }

    func configureOpenPanel(_ panel: NSOpenPanel) {
        panel.allowedContentTypes = [.pdf, .epub, .init(filenameExtension: "docx")].compactMap { $0 }
        panel.allowsOtherFileTypes = false
    }

    func loadDocument(_ url: URL) {
        guard let kind = ReaderDocumentKind.kind(for: url) else { return }
        saveCurrentAIConversationBeforeDocumentChange()
        resetEmbeddingStateForDocumentChange()
        switch kind {
        case .pdf:
            loadPDF(url)
        case .epub, .docx:
            loadWebDocument(url, kind: kind)
        }
    }

    func loadPDF(_ url: URL) {
        guard let document = PDFDocument(url: url) else { return }
        currentDocumentKind = .pdf
        pdfView.isHidden = false
        webView.isHidden = true
        pdfView.document = document
        currentFileURL = url
        currentFileMD5 = fileMD5(for: url)
        sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
        pdfWordRecordStore = currentFileMD5.map { PDFWordRecordStore(fileMD5: $0) }
        webWordRecordStore = nil
        aiConversationStore = currentFileMD5.map { AIConversationStore(fileMD5: $0) }
        currentWebPlainText = ""
        currentWebSelectedText = ""
        pdfAgentIndex = nil
        isBuildingDocumentAgentIndex = false
        documentAgentIndexGeneration += 1
        pendingDocumentAgentIndexCallbacks.removeAll()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        cancelScheduledEmbeddingWarmup()
        currentTOCItems = []
        pdfTOCDestinations = [:]
        schedulePDFTOCBuild(for: url, displayBox: pdfView.displayBox)
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil
        highlightedSelectionKeys.removeAll()
        storedWordRecords = loadStoredWordRecords()
        storedWebWordRecords.removeAll()
        restoreStoredWordAnnotations()
        aiPanel.loadLinkedWordBubbles(pdfWordRecordStore?.linkedWordBubbles(from: storedWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        updateCoverThumbnail(from: document)
        pageLayoutButton.isHidden = false
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
    }

    func schedulePDFTOCBuild(for url: URL, displayBox: PDFDisplayBox) {
        pdfTOCGeneration += 1
        let generation = pdfTOCGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let document = PDFDocument(url: url) else { return }
            let toc = ReaderTOCHelper.pdfTOCItems(from: document, displayBox: displayBox)
            DispatchQueue.main.async {
                guard let self,
                      self.pdfTOCGeneration == generation,
                      self.currentFileURL == url else {
                    return
                }
                self.currentTOCItems = toc.items
                self.pdfTOCDestinations = toc.destinations
            }
        }
    }

    func loadWebDocument(_ url: URL, kind: ReaderDocumentKind) {
        do {
            let document = try WebDocumentLoader.load(url: url)
            currentDocumentKind = kind
            pdfView.isHidden = true
            pdfDimOverlay.isHidden = true
            webView.isHidden = false
            pdfView.document = nil
            currentFileURL = url
            currentFileMD5 = fileMD5(for: url)
            sessionStore = ReaderSessionStore(fileMD5: currentFileMD5)
            pdfWordRecordStore = nil
            webWordRecordStore = currentFileMD5.map { WebWordRecordStore(fileMD5: $0) }
            aiConversationStore = currentFileMD5.map { AIConversationStore(fileMD5: $0) }
            pdfAgentIndex = nil
            isBuildingDocumentAgentIndex = false
            documentAgentIndexGeneration += 1
            pendingDocumentAgentIndexCallbacks.removeAll()
            pendingPDFWordRecords.removeAll()
            pendingWebWordRecords.removeAll()
            cancelScheduledEmbeddingWarmup()
            currentWebPlainText = document.plainText
            currentWebSelectedText = ""
            currentWebSelectionContext = ""
            currentTOCItems = document.tocItems
            pdfTOCDestinations = [:]
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
            webZoomPercent = 100
            webScrollProgress = 0
            highlightedSelectionKeys.removeAll()
            storedWordRecords.removeAll()
            storedWebWordRecords = loadStoredWebWordRecords()
            aiPanel.loadLinkedWordBubbles(webWordRecordStore?.linkedWordBubbles(from: storedWebWordRecords) ?? [])
            loadSavedAIConversationIfNeeded()
            searchResults.removeAll()
            searchResultIndex = 0
            lastSearchQuery = ""
            searchOverlay.setResultText("")
            aiPanel.setSelectedText("")
            titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
            if let coverImageURL = document.coverImageURL, let image = NSImage(contentsOf: coverImageURL) {
                coverImageView.image = image
            } else {
                coverImageView.image = NSImage(systemSymbolName: kind == .epub ? "book.closed" : "doc.text", accessibilityDescription: nil)
            }
            coverImageView.isHidden = false
            pageLayoutButton.isHidden = true
            pageLabel.stringValue = "0%"
            zoomField.stringValue = "100%"
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
            applyReaderTheme()
            applyWebZoomToPage()
            restoreWebProgressAfterLoad()
            RecentDocumentsStore.record(url: url, kind: kind)
            saveSession()
            scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func showTableOfContents() {
        guard !currentTOCItems.isEmpty else {
            NSSound.beep()
            return
        }

        let menu = NSMenu()
        for (index, item) in currentTOCItems.prefix(120).enumerated() {
            let indent = String(repeating: "  ", count: min(item.level, 4))
            let menuItem = NSMenuItem(title: "\(indent)\(item.title)", action: #selector(selectTableOfContentsItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = index
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: tocButton.bounds.height + 4), in: tocButton)
    }

    @objc func showRecentDocuments() {
        let items = RecentDocumentsStore.load()
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let controller = RecentDocumentsPanelController()
        recentDocumentsPanelController = controller
        controller.show(
            items: items,
            attachedTo: window,
            onOpen: { [weak self] path in
                self?.loadDocument(URL(fileURLWithPath: path))
            },
            onClear: {
                RecentDocumentsStore.clear()
            },
            onRemoveItem: { path in
                RecentDocumentsStore.remove(path: path)
            },
            onClearVectorCache: { [weak self] path in
                self?.clearVectorCacheForShelfItem(path: path)
            },
            onClearWordRecords: { [weak self] path in
                self?.clearWordRecordsForShelfItem(path: path)
            },
            onClose: { [weak self] in
                self?.recentDocumentsPanelController = nil
            }
        )
    }

    func clearVectorCacheForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        if currentFileMD5 == documentID {
            embeddingBackfillGeneration += 1
            isPreparingPDFEmbeddings = false
            isEmbeddingBackfillPaused = false
            queuedEmbeddingPriorityPageIndex = nil
            pdfAgentIndex = nil
            documentAgentIndexGeneration += 1
            pendingDocumentAgentIndexCallbacks.removeAll()
            embeddingStatusLabel.stringValue = AppText.localized("向量索引：已清除当前书", "Embedding: current book cleared")
            embeddingStatusLabel.isHidden = false
            updateEmbeddingControlButtons()
        }
    }

    func clearWordRecordsForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        if currentFileMD5 == documentID {
            clearCurrentBookWordRecords()
            return
        }
        PDFWordRecordStore(fileMD5: documentID).save([])
        WebWordRecordStore(fileMD5: documentID).save([])
    }


    @objc func selectTableOfContentsItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, currentTOCItems.indices.contains(index) else { return }
        let item = currentTOCItems[index]
        if currentDocumentKind == .pdf {
            jumpToPDFTOCItem(item)
        } else {
            jumpToWebTOCItem(item)
        }
    }

    func jumpToPDFTOCItem(_ item: ReaderTOCItem) {
        guard let destination = pdfTOCDestinations[item.href],
              let page = destination.page,
              let pageIndex = pdfView.document?.index(for: page) else {
            return
        }

        clearAISelectionForNavigation()
        pdfView.go(to: destination)
        lastPageIndex = pageIndex
        updatePageLabel()
        saveSession()
    }

    func jumpToWebTOCItem(_ item: ReaderTOCItem) {
        webView.evaluateJavaScript(ReaderTOCHelper.webJumpScript(for: item))
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

    func openDocument(_ url: URL) {
        loadDocument(url)
    }

    @objc func openPDFInCurrentDirectory() {
        guard let url = currentFileURL else { return }
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.loadDocument(selectedURL)
        }
    }
}
