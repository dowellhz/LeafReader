import Cocoa

extension ReaderWindowController {
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
              sender.window != nil else { return }
        closeVocabularyPanel()
    }

    func closeVocabularyPanel() {
        vocabularyPanelController.close()
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
        let filter = selectedVocabularyListFilter(in: vocabularyPanelController.rootView)
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

    func safeExportFileName(_ name: String) -> String {
        VocabularyExporter.safeFileName(name)
    }

}
