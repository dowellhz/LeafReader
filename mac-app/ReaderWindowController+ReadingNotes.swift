import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let readingNoteAnnotationPrefix = "leaf-note"
    private static let maxReadingNoteHighlightLines = 24

    func loadReadingNotesForCurrentDocument() {
        guard let documentID = currentFileMD5 else {
            storedReadingNotes.removeAll()
            return
        }
        storedReadingNotes = ReadingNoteStore.shared.load(documentID: documentID)
    }

    func closeReadingNotePanelsForDocumentTransition() {
        let openNotePanels = Array(readingNotePanelControllers.values)
        for controller in openNotePanels {
            controller.close()
        }
        readingNotePanelControllers.removeAll()
        closeReadingNotesListPanel()
    }

    func restoreReadingNoteAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        clearReadingNoteAnnotations()
        for note in storedReadingNotes {
            addReadingNoteAnnotation(note)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func createReadingNoteFromCurrentSelection(text: String) {
        guard let documentID = currentFileMD5 else {
            NSSound.beep()
            return
        }
        let quote = readingNoteQuoteForCurrentSelection(fallback: text)
        guard !quote.isEmpty else {
            NSSound.beep()
            return
        }
        let locator = readingNoteLocatorForCurrentSelection(quote: quote)
        let now = Date()
        let note = ReadingNote(
            id: UUID().uuidString,
            documentID: documentID,
            documentTitle: documentTitleForAI(),
            documentKind: currentDocumentKind.readingNoteKind,
            quote: quote,
            markdown: ReadingNoteMarkdown.defaultBody(quote: quote),
            locator: locator,
            createdAt: now,
            updatedAt: now
        )
        openReadingNotePanel(note)
    }

    private func readingNoteQuoteForCurrentSelection(fallback text: String) -> String {
        guard currentDocumentKind == .pdf,
              let selection = pdfView.currentSelection,
              let document = pdfView.document else {
            return ReadingNoteTextPolicy.normalizeQuote(text)
        }
        let lines = selection.selectionsByLine().compactMap { line -> ReadingNoteTextPolicy.PDFLine? in
            guard let value = line.string,
                  let page = line.pages.first else { return nil }
            let bounds = line.bounds(for: page)
            guard !bounds.isEmpty else { return nil }
            return ReadingNoteTextPolicy.PDFLine(
                text: value,
                pageIndex: document.index(for: page),
                bounds: bounds
            )
        }
        let normalized = ReadingNoteTextPolicy.normalizePDFLines(lines)
        return normalized.isEmpty ? ReadingNoteTextPolicy.normalizeQuote(text) : normalized
    }

    func openReadingNotePanel(_ note: ReadingNote) {
        if let controller = readingNotePanelControllers[note.id] {
            presentReadingNotePanel(controller)
            return
        }
        let controller = ReadingNotePanelController(note: note) { [weak self] savedNote in
            self?.saveReadingNote(savedNote)
        } onClose: { [weak self] id in
            self?.readingNotePanelControllers[id] = nil
        } onShowNotes: { [weak self] in
            self?.presentReadingNotesListPanel()
        } onExportNote: { [weak self] note in
            self?.exportSingleReadingNoteMarkdown(note)
        } onDeleteNote: { [weak self] note in
            self?.deleteReadingNoteWithConfirmation(note)
        } onDocumentQuestionPrompt: { [weak self] request, completion in
            self?.documentAgentPrompt(
                question: request.question,
                questionSubject: request.questionSubject,
                context: request.context,
                showsEvidenceBubbles: false,
                completion: completion
            )
        }
        readingNotePanelControllers[note.id] = controller
        presentReadingNotePanel(controller)
    }

    @objc func showReadingNotesPanel(_ sender: Any?) {
        presentReadingNotesListPanel()
    }

    func presentReadingNotesListPanel() {
        let controller = readingNotesPanelController ?? ReadingNotesPanelController()
        readingNotesPanelController = controller
        controller.onOpenNote = { [weak self] note in
            guard let self else { return }
            self.closeReadingNotesListPanel()
            self.jumpToReadingNote(note)
            self.openReadingNotePanel(note)
        }
        controller.onDeleteNote = { [weak self] note in
            self?.deleteReadingNote(note)
        }
        controller.onExport = { [weak self] in
            self?.exportReadingNotesMarkdown(nil)
        }
        controller.onClose = { [weak self] in
            self?.readingNotesPanelController = nil
        }
        controller.show(notes: storedReadingNotes, parent: window)
        raiseReadingNotesListPanel()
    }

    func closeReadingNotesListPanel() {
        readingNotesPanelController?.close(attachedTo: window)
        readingNotesPanelController = nil
    }

    private func presentReadingNotePanel(_ controller: ReadingNotePanelController) {
        controller.show(relativeTo: window)
        raiseReadingNotePanel(controller)
    }

    private func raiseReadingNotePanel(_ controller: ReadingNotePanelController) {
        guard let panel = controller.window else { return }
        attachReadingChildWindow(panel)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func raiseReadingNotesListPanel() {
        guard let panel = readingNotesPanelController?.panel else { return }
        attachReadingChildWindow(panel)
        for sibling in window?.childWindows ?? [] where sibling !== panel {
            panel.order(.above, relativeTo: sibling.windowNumber)
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func attachReadingChildWindow(_ panel: NSWindow) {
        guard let parent = window else { return }
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
    }

    func jumpToReadingNote(_ note: ReadingNote) {
        if currentDocumentKind == .pdf,
           let first = note.locator.pdfFragments?.first {
            jumpToPDFPage(index: first.pageIndex, skipIfCurrentPage: false)
            return
        }
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderScrollToNote && window.leafReaderScrollToNote(\(jsStringLiteral(note.id)), \(note.locator.webAnchor?.scrollProgress ?? webScrollProgress));")
    }

    func saveReadingNote(_ note: ReadingNote) {
        if let index = storedReadingNotes.firstIndex(where: { $0.id == note.id }) {
            storedReadingNotes[index] = note
        } else {
            storedReadingNotes.append(note)
        }
        if ReadingNoteStore.shared.upsert(note) {
            readingNotesPanelController?.update(notes: storedReadingNotes)
            if currentDocumentKind == .pdf {
                addReadingNoteAnnotation(note)
            } else {
                markCurrentWebSelectionAsReadingNote(id: note.id)
            }
        }
    }

    func deleteReadingNote(_ note: ReadingNote) {
        guard ReadingNoteStore.shared.delete(id: note.id) else {
            NSSound.beep()
            return
        }
        storedReadingNotes.removeAll { $0.id == note.id }
        readingNotePanelControllers[note.id]?.closeWithoutSaving()
        readingNotePanelControllers[note.id] = nil
        if currentDocumentKind == .pdf {
            removeReadingNoteAnnotation(id: note.id)
        } else {
            removeWebReadingNoteHighlight(id: note.id)
        }
        readingNotesPanelController?.update(notes: storedReadingNotes)
    }

    func deleteReadingNoteWithConfirmation(_ note: ReadingNote) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("删除这条阅读笔记？", "Delete this reading note?")
        alert.informativeText = AppText.localized("删除后不可恢复。", "This cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("删除", "Delete"))
        alert.addButton(withTitle: AppText.cancel)
        alert.applyLeafStyle()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteReadingNote(note)
    }

    func exportSingleReadingNoteMarkdown(_ note: ReadingNote) {
        let savePanel = readingNotesSavePanel(fileNameSuffix: "note")
        savePanel.beginSheetModal(for: window ?? NSWindow()) { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let output = ReadingNoteExporter.markdown(documentTitle: note.documentTitle, notes: [note])
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.applyLeafStyle()
                alert.runModal()
            }
        }
    }

    @objc func exportReadingNotesMarkdown(_ sender: Any?) {
        guard !storedReadingNotes.isEmpty else {
            NSSound.beep()
            return
        }
        let savePanel = readingNotesSavePanel(fileNameSuffix: "notes")
        savePanel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            do {
                let output = ReadingNoteExporter.markdown(
                    documentTitle: self.documentTitleForAI(),
                    notes: self.storedReadingNotes.sortedByCreatedAt()
                )
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.applyLeafStyle()
                alert.runModal()
            }
        }
    }

    private func readingNotesSavePanel(fileNameSuffix: String) -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = "\(safeExportFileName(documentTitleForAI()))-\(fileNameSuffix).md"
        return savePanel
    }

    private func readingNoteLocatorForCurrentSelection(quote: String) -> ReadingNote.Locator {
        if currentDocumentKind == .pdf,
           let selection = pdfView.currentSelection {
            let fragments = selection.selectionsByLine().prefix(Self.maxReadingNoteHighlightLines).compactMap { line -> ReadingNote.PDFFragment? in
                guard let page = line.pages.first,
                      let document = pdfView.document else { return nil }
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { return nil }
                return ReadingNote.PDFFragment(
                    pageIndex: document.index(for: page),
                    bounds: StoredPDFWordRect(bounds)
                )
            }
            return ReadingNote.Locator(pdfFragments: fragments, webAnchor: nil)
        }
        let anchor = ReadingNote.WebAnchor(
            selectedText: quote,
            context: currentWebSelectionContext,
            occurrenceIndex: currentWebSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress
        )
        return ReadingNote.Locator(pdfFragments: nil, webAnchor: anchor)
    }

    private func addReadingNoteAnnotation(_ note: ReadingNote) {
        guard currentDocumentKind == .pdf,
              let fragments = note.locator.pdfFragments,
              !fragments.isEmpty else {
            return
        }
        for (index, fragment) in fragments.enumerated() {
            guard let page = pdfView.document?.page(at: fragment.pageIndex) else { continue }
            let key = "\(Self.readingNoteAnnotationPrefix):\(note.id):\(index)"
            if let existing = page.annotations.first(where: { $0.contents == key }) {
                existing.color = readingNoteHighlightColor()
                continue
            }
            let bounds = fragment.bounds.cgRect.insetBy(dx: -1.5, dy: -1)
            guard !bounds.isEmpty else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = readingNoteHighlightColor()
            annotation.contents = key
            page.addAnnotation(annotation)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func removeReadingNoteAnnotation(id: String) {
        guard let document = pdfView.document else { return }
        let prefix = "\(Self.readingNoteAnnotationPrefix):\(id):"
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix(prefix) == true {
                page.removeAnnotation(annotation)
            }
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func readingNoteID(at event: NSEvent) -> String? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)
        let prefix = "\(Self.readingNoteAnnotationPrefix):"
        guard let contents = page.annotations.first(where: { annotation in
            annotation.contents?.hasPrefix(prefix) == true
                && annotation.bounds.insetBy(dx: -3, dy: -5).contains(pointOnPage)
        })?.contents else {
            return nil
        }
        return contents
            .dropFirst(prefix.count)
            .split(separator: ":")
            .first
            .map(String.init)
    }

    func restoreWebReadingNoteHighlights(completion: (() -> Void)? = nil) {
        guard currentDocumentKind != .pdf else {
            completion?()
            return
        }
        let payload = storedReadingNotes.compactMap(webHighlightPayload(for:))
        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            completion?()
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreNoteHighlights && window.leafReaderRestoreNoteHighlights(\(json));") { _, _ in
            completion?()
        }
    }

    private func webHighlightPayload(for note: ReadingNote) -> [String: Any]? {
        guard let anchor = note.locator.webAnchor else { return nil }
        var item: [String: Any] = [
            "id": note.id,
            "selectedText": anchor.selectedText,
            "context": anchor.context
        ]
        if let occurrenceIndex = anchor.occurrenceIndex {
            item["occurrenceIndex"] = occurrenceIndex
        }
        return item
    }

    private func removeWebReadingNoteHighlight(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderRemoveNoteHighlight && window.leafReaderRemoveNoteHighlight(\(jsStringLiteral(id)));")
    }

    private func markCurrentWebSelectionAsReadingNote(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderMarkSelectionAsNote && window.leafReaderMarkSelectionAsNote(\(jsStringLiteral(id)));") { [weak self] result, _ in
            guard (result as? Bool) != true else { return }
            self?.restoreWebReadingNoteHighlights()
        }
    }

    private func clearReadingNoteAnnotations() {
        guard let document = pdfView.document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix("\(Self.readingNoteAnnotationPrefix):") == true {
                page.removeAnnotation(annotation)
            }
        }
    }

    private func readingNoteHighlightColor() -> NSColor {
        switch ReaderTheme.selected {
        case .eyeCare:
            return NSColor(red: 0.80, green: 0.58, blue: 0.15, alpha: 0.30)
        case .dark:
            return NSColor(red: 0.57, green: 0.79, blue: 1.0, alpha: 0.34)
        case .original:
            return NSColor(red: 0.57, green: 0.79, blue: 1.0, alpha: 0.30)
        }
    }
}

private extension ReaderDocumentKind {
    var readingNoteKind: String {
        switch self {
        case .pdf: return "pdf"
        case .epub: return "epub"
        case .docx: return "docx"
        }
    }
}
