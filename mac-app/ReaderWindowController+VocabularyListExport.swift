import Cocoa

extension ReaderWindowController {
    private static let vocabularyContextSelectionInset = CGSize(width: -120, height: -36)
    private static let vocabularyContextFallbackInset = CGSize(width: -80, height: -24)

    func findView(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    @objc func closeVocabularyBook(_ sender: NSButton) {
        guard sender.identifier?.rawValue == "closeVocabularyBook",
              let panel = sender.window else { return }
        closeVocabularyPanel(panel)
    }

    func closeVocabularyPanel(_ panel: NSWindow) {
        commitPendingVocabularyAnswerIfNeeded()
        removeVocabularyPanelActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: window)
        vocabularyPanel = nil
    }

    func installVocabularyPanelActivationObserver() {
        removeVocabularyPanelActivationObserver()
        vocabularyPanelActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let panel = self?.vocabularyPanel else { return }
            ModalOverlayManager.shared.reactivate(panel)
        }
    }

    func removeVocabularyPanelActivationObserver() {
        if let vocabularyPanelActivationObserver {
            NotificationCenter.default.removeObserver(vocabularyPanelActivationObserver)
            self.vocabularyPanelActivationObserver = nil
        }
    }

    @objc func exportVocabularyMarkdown(_ sender: NSButton) {
        exportVocabulary(format: .markdown)
    }

    @objc func exportVocabularyCSV(_ sender: NSButton) {
        exportVocabulary(format: .csv)
    }

    enum VocabularyExportFormat {
        case markdown
        case csv

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .csv: return "csv"
            }
        }
    }

    func exportVocabulary(format: VocabularyExportFormat) {
        let records = VocabularyExporter.exportableRecords(vocabularyExporterRecords(currentVocabularyExportRecordsForActiveFilter()))
        guard !records.isEmpty else {
            NSSound.beep()
            return
        }

        let savePanel = vocabularyExportSavePanel(format: format)
        savePanel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let output: String
                switch format {
                case .markdown:
                    output = self?.vocabularyMarkdown(records) ?? ""
                case .csv:
                    output = self?.vocabularyCSV(records) ?? ""
                }
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.applyLeafStyle()
                alert.runModal()
            }
        }
    }

    func vocabularyExportSavePanel(format: VocabularyExportFormat) -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = "\(safeExportFileName(documentTitleForAI()))-vocabulary.\(format.fileExtension)"
        return savePanel
    }

    func vocabularyExporterRecords(_ records: [VocabularyExportRecord]) -> [VocabularyExporter.Record] {
        let source = documentTitleForAI()
        return records.map { record in
            VocabularyExporter.Record(
                word: record.word,
                answer: record.answer,
                location: record.location,
                context: record.context,
                source: source,
                createdAt: record.createdAt
            )
        }
    }

    func currentVocabularyExportRecordsForActiveFilter() -> [VocabularyExportRecord] {
        let filter = selectedVocabularyListFilter(in: vocabularyPanel?.contentView)
        return vocabularyRecords(currentVocabularyExportRecords, matching: filter)
    }

    func vocabularyMarkdown(_ records: [VocabularyExporter.Record]) -> String {
        VocabularyExporter.markdown(
            records: records,
            documentTitle: documentTitleForAI(),
            labels: VocabularyExporter.MarkdownLabels(
                titleSuffix: AppText.localized("背单词", "Vocabulary"),
                exportedAt: AppText.localized("导出时间", "Exported at"),
                wordCount: AppText.localized("单词数量", "Word count"),
                location: AppText.localized("位置", "Location"),
                context: AppText.localized("原文上下文", "Original context")
            )
        ) { record in
            vocabularyAnswerBody(record.answer, word: record.word)
        }
    }

    func vocabularyCSV(_ records: [VocabularyExporter.Record]) -> String {
        VocabularyExporter.csv(records: records) { record in
            vocabularyAnswerBody(record.answer, word: record.word)
        }
    }

    func pdfWordContext(for record: StoredPDFWordRecord) -> String {
        if let context = VocabularyExporter.nonEmptyText(record.context) {
            return context
        }
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return "" }
        let pageText = page.string ?? ""
        let selectedText = VocabularyExporter.trimmed(record.word)
        if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: pageText, radius: 24) {
            return context
        }
        let expandedBounds = record.bounds.cgRect.insetBy(
            dx: Self.vocabularyContextSelectionInset.width,
            dy: Self.vocabularyContextSelectionInset.height
        )
        if let nearbyText = page.selection(for: expandedBounds)?.string,
           let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: nearbyText, radius: 24) {
            return context
        }
        let fallbackBounds = record.bounds.cgRect.insetBy(
            dx: Self.vocabularyContextFallbackInset.width,
            dy: Self.vocabularyContextFallbackInset.height
        )
        return ReaderAIContextBuilder.normalizeWhitespace(page.selection(for: fallbackBounds)?.string ?? "")
    }

    func safeExportFileName(_ name: String) -> String {
        VocabularyExporter.safeFileName(name)
    }

}
