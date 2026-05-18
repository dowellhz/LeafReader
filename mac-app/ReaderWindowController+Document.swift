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
        sessionSaveTask.flush()
        flushCurrentBookWordRecordSaves()
        saveCurrentAIConversationBeforeDocumentChange()
        resetEmbeddingStateForDocumentChange()
        switch kind {
        case .pdf:
            loadPDF(url)
        case .epub, .docx:
            loadWebDocument(url, kind: kind)
        }
    }

    func handleDroppedDocumentURLs(_ urls: [URL]) {
        ReaderDocumentImportCoordinator.handleDroppedDocumentURLs(urls, controller: self)
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
        webPlainTextGeneration += 1
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
        clearAISourceUnderlineTracking()
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
            webPlainTextGeneration += 1
            let webPlainTextGeneration = webPlainTextGeneration
            currentWebSelectedText = ""
            currentWebSelectionContext = ""
            currentWebSelectionOccurrenceIndex = nil
            currentTOCItems = document.tocItems
            pdfTOCDestinations = [:]
            accumulatedPDFTrackpadScroll = 0
            didTurnPageForCurrentPDFTrackpadGesture = false
            lastPDFTrackpadEdgeDirection = nil
            webZoomPercent = 100
            webScrollProgress = 0
            highlightedSelectionKeys.removeAll()
            clearAISourceUnderlineTracking()
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
            updatePageLabelTextColor()
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
        } catch {
            let alert = NSAlert(error: error)
            alert.applyLeafWhiteStyle()
            alert.runModal()
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
        showRecentDocumentsPanel(focusPath: nil, priorityPaths: [])
    }

    func showRecentDocumentsPanel(focusPath: String?, priorityPaths: [String] = []) {
        let items = sortedRecentDocuments(priorityPaths: priorityPaths)
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let controller = RecentDocumentsPanelController()
        recentDocumentsPanelController = controller
        controller.show(
            items: items,
            attachedTo: window,
            focusPath: focusPath,
            onOpen: { [weak self] path in
                self?.loadDocument(URL(fileURLWithPath: path))
            },
            onClear: { [weak self] in
                self?.unloadCurrentDocumentForShelfRemoval()
                RecentDocumentsStore.clear()
            },
            onRemoveItem: { [weak self] path, options in
                self?.removeShelfItem(
                    path: path,
                    clearVectorCache: options.clearVectorCache,
                    clearWordRecords: options.clearWordRecords,
                    clearAIData: options.clearAIData
                )
            },
            onClearVectorCache: { [weak self] path in
                self?.clearVectorCacheForShelfItem(path: path)
            },
            onClearWordRecords: { [weak self] path in
                self?.clearWordRecordsForShelfItem(path: path)
            },
            onClearAIData: { [weak self] path in
                self?.clearAIDataForShelfItem(path: path)
            },
            onImport: { [weak self] urls in
                guard let self else { return }
                ReaderDocumentImportCoordinator.importDroppedDocumentsToShelf(urls, controller: self)
            },
            onClose: { [weak self] in
                self?.recentDocumentsPanelController = nil
            }
        )
    }

    func sortedRecentDocuments(priorityPaths: [String]) -> [RecentDocumentItem] {
        let items = RecentDocumentsStore.load()
        guard !priorityPaths.isEmpty else {
            return items.sorted { lhs, rhs in
                if lhs.openedAt != rhs.openedAt {
                    return lhs.openedAt > rhs.openedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        var priorityIndex: [String: Int] = [:]
        for (index, path) in priorityPaths.enumerated() where priorityIndex[path] == nil {
            priorityIndex[path] = index
        }
        return items.sorted { lhs, rhs in
            let lhsPriority = priorityIndex[lhs.path]
            let rhsPriority = priorityIndex[rhs.path]
            switch (lhsPriority, rhsPriority) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if lhs.openedAt != rhs.openedAt {
                    return lhs.openedAt > rhs.openedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func removeShelfItem(path: String, clearVectorCache: Bool, clearWordRecords: Bool, clearAIData: Bool) {
        let documentID = fileMD5(for: URL(fileURLWithPath: path))
        if currentFileURL?.path == path {
            unloadCurrentDocumentForShelfRemoval()
        }
        if let documentID {
            ReaderSessionStore(fileMD5: documentID).clearProgress()
        }
        if clearVectorCache {
            clearVectorCacheForShelfItem(path: path)
        }
        if clearWordRecords {
            clearWordRecordsForShelfItem(path: path)
        }
        if clearAIData, let documentID {
            clearAIDataForDocument(documentID: documentID, wasCurrentDocument: currentFileMD5 == documentID)
            if !clearWordRecords {
                clearWordRecordsForShelfItem(path: path)
            }
        }
        RecentDocumentsStore.remove(path: path)
    }

    func unloadCurrentDocumentForShelfRemoval() {
        guard currentFileURL != nil else { return }
        saveCurrentAIConversationBeforeDocumentChange()
        saveSession()
        resetEmbeddingStateForDocumentChange()

        pdfTOCGeneration += 1
        documentAgentIndexGeneration += 1
        isBuildingDocumentAgentIndex = false
        pendingDocumentAgentIndexCallbacks.removeAll()
        pendingEmbeddingReadyCallbacks.removeAll()

        pdfView.document = nil
        pdfView.isHidden = false
        pdfDimOverlay.isHidden = true
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.isHidden = true

        currentFileURL = nil
        currentFileMD5 = nil
        currentDocumentKind = .pdf
        sessionStore = ReaderSessionStore(fileMD5: nil)
        pdfWordRecordStore = nil
        webWordRecordStore = nil
        aiConversationStore = nil
        pdfAgentIndex = nil
        currentWebPlainText = ""
        webPlainTextGeneration += 1
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentTOCItems = []
        pdfTOCDestinations = [:]
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        storedWordRecords.removeAll()
        storedWebWordRecords.removeAll()
        highlightedSelectionKeys.removeAll()
        currentVocabularyExportRecords.removeAll()
        accumulatedPDFTrackpadScroll = 0
        didTurnPageForCurrentPDFTrackpadGesture = false
        lastPDFTrackpadEdgeDirection = nil
        lastPageIndex = nil
        webScrollProgress = 0

        aiPanel.loadLinkedWordBubbles([])
        aiPanel.clearSelectedText()
        titleLabel.stringValue = "Leaf Reader"
        coverImageView.image = nil
        coverImageView.isHidden = true
        pageLayoutButton.isHidden = true
        pageLabel.stringValue = AppText.noPDF
        updatePageLabelTextColor()
        zoomField.stringValue = "100%"
        updateEmbeddingControlButtons()
        applyReaderTheme()
    }

    func clearVectorCacheForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        embeddingStoreQueue.async { [weak self] in
            self?.pdfEmbeddingStore?.deleteDocument(documentID: documentID)
        }
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

    func clearAIDataForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        clearAIDataForDocument(documentID: documentID, wasCurrentDocument: currentFileMD5 == documentID)
        clearWordRecordsForShelfItem(path: path)
    }

    private func clearAIDataForDocument(documentID: String, wasCurrentDocument: Bool) {
        if wasCurrentDocument {
            aiConversationSaveTask.cancel()
            pendingAIConversationToSave = nil
            clearAISourceUnderlines()
            aiPanel.loadLinkedWordBubbles([])
            aiPanel.clearSelectedText()
        }
        AIConversationStore(fileMD5: documentID).clear()
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
                self.pdfAgentIndex = nil
                self.isBuildingDocumentAgentIndex = false
                self.pendingDocumentAgentIndexCallbacks.removeAll()
                self.scheduleDocumentEmbeddingWarmup(priorityPageIndex: self.currentEmbeddingPriorityIndex())
            }
        }
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
        guard let tocDestination = pdfTOCDestinations[item.href],
              let page = pdfView.document?.page(at: tocDestination.pageIndex) else {
            return
        }

        clearAISelectionForNavigation()
        let beforePageIndex = currentPageIndex()
        let destination = PDFDestination(page: page, at: tocDestination.point)
        pdfView.go(to: destination)
        lastPageIndex = tocDestination.pageIndex
        updatePageLabel()
        saveSession()
        recordPageJump(source: "toc", before: beforePageIndex, after: currentPageIndex(), detail: item.title)
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
