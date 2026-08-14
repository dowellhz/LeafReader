import Cocoa

extension ReaderWindowController {
    @objc func openPDF() {
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadSelectedDocument(url)
        }
    }

    func configureOpenPanel(_ panel: NSOpenPanel) {
        DocumentOpenPanelConfiguration.apply(to: panel)
    }

    func loadDocument(_ url: URL) {
        guard let kind = ReaderDocumentKind.kind(for: url) else { return }
        activeDocumentLoadCancellationToken?.cancel()
        activeDocumentLoadCancellationToken = nil
        stopReadAloudImmediately()
        SpeechPlaybackCoordinator.shared.shutdownRuntime(.kokoro)
        documentLoadGeneration += 1
        let generation = documentLoadGeneration
        showDocumentLoading(for: url)
        sessionSaveTask.cancel()
        flushCurrentBookWordRecordSaves()
        saveCurrentAIConversationBeforeDocumentChange()
        resetEmbeddingStateForDocumentChange()
        let cancellationToken = DocumentLoadCancellationToken()
        activeDocumentLoadCancellationToken = cancellationToken
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let contentIdentifiers = try DocumentIdentity.contentIdentifiers(
                    for: url,
                    isCancelled: { cancellationToken.isCancelled }
                )
                try cancellationToken.checkCancellation()
                guard let self else { return }
                let metadataID = DocumentIdentity.migrationMetadataID(
                    fastID: DocumentIdentity.fastID(for: url),
                    cachedLegacyID: self.cachedLegacyMD5(for: url),
                    computedLegacyID: contentIdentifiers.legacyMD5
                )
                let documentID = DocumentIdentity.storageID(
                    contentID: contentIdentifiers.contentID,
                    metadataID: metadataID,
                    legacyID: contentIdentifiers.legacyMD5,
                    hasStoredData: self.hasStoredDocumentData(documentID:)
                )
                try cancellationToken.checkCancellation()
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.documentLoadGeneration == generation,
                          self.activeDocumentLoadCancellationToken === cancellationToken else {
                        return
                    }
                    switch kind {
                    case .pdf:
                        self.activeDocumentLoadCancellationToken = nil
                        self.loadPDF(url, documentID: documentID, generation: generation)
                    case .epub, .docx:
                        self.loadWebDocument(
                            url,
                            kind: kind,
                            documentID: documentID,
                            generation: generation,
                            cancellationToken: cancellationToken
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.documentLoadGeneration == generation else { return }
                    self.activeDocumentLoadCancellationToken = nil
                    self.showDocumentLoadingFailure(error, generation: generation)
                }
            }
        }
    }

    func showDocumentLoading(for url: URL) {
        loadingLabel.stringValue = AppText.localized("正在打开 \(url.lastPathComponent)...", "Opening \(url.lastPathComponent)...")
        loadingOverlay.isHidden = false
        loadingIndicator.startAnimation(nil)
    }

    func hideDocumentLoading(generation: Int) {
        guard documentLoadGeneration == generation else { return }
        loadingIndicator.stopAnimation(nil)
        loadingOverlay.isHidden = true
    }

    func showDocumentLoadingFailure(_ error: Error, generation: Int) {
        guard documentLoadGeneration == generation else { return }
        pendingPDFTOCBuildRequest = nil
        pendingPDFCoverThumbnailRequest = nil
        hideDocumentLoading(generation: generation)
        let alert = NSAlert(error: error)
        alert.applyLeafStyle()
        alert.runModal()
    }

    func finishDocumentLoadingAfterAIBubbles(generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.documentLoadGeneration == generation else { return }
            self.aiPanel.flushTranscriptLayout()
            self.aiPanel.layoutSubtreeIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentLoadGeneration == generation else { return }
                self.aiPanel.flushTranscriptLayout()
                self.aiPanel.layoutSubtreeIfNeeded()
                self.hideDocumentLoading(generation: generation)
                self.finishVisibleDocumentWork(generation: generation)
            }
        }
    }

    private func finishVisibleDocumentWork(generation: Int) {
        guard documentLoadGeneration == generation, currentDocumentKind == .pdf else { return }
        startPendingPDFTOCBuildIfNeeded()
        startPendingPDFCoverThumbnailIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.documentLoadGeneration == generation,
                  self.currentDocumentKind == .pdf else { return }
            self.restoreStoredWordAnnotations()
            self.restoreReadingNoteAnnotations()
        }
    }

    func handleDroppedDocumentURLs(_ urls: [URL]) {
        ReaderDocumentImportCoordinator.handleDroppedDocumentURLs(urls, controller: self)
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
            self?.loadSelectedDocument(selectedURL)
        }
    }

    func loadSelectedDocument(_ url: URL) {
        guard ReaderDocumentKind.kind(for: url) != nil else {
            NSSound.beep()
            return
        }
        loadDocument(url)
    }
}
