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
        stopReadAloudImmediately()
        documentLoadGeneration += 1
        let generation = documentLoadGeneration
        showDocumentLoading(for: url)
        sessionSaveTask.cancel()
        flushCurrentBookWordRecordSaves()
        saveCurrentAIConversationBeforeDocumentChange()
        resetEmbeddingStateForDocumentChange()
        switch kind {
        case .pdf:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentLoadGeneration == generation else { return }
                self.loadPDF(url, generation: generation)
            }
        case .epub, .docx:
            loadWebDocument(url, kind: kind, generation: generation)
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
            }
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
