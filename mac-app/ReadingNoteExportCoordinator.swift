import Cocoa

final class ReadingNoteExportCoordinator {
    struct Request {
        let format: ReadingNoteExporter.Format
        let scope: ReadingNoteExporter.Scope
    }

    func beginExport(
        notes: [ReadingNote],
        documentTitle: String,
        allowsScopeSelection: Bool,
        fileNameSuffix: String,
        parent: NSWindow?
    ) {
        let scopePopup = ExportPanelSupport.popup(for: ReadingNoteExporter.Scope.allCases.map(\.title))
        scopePopup.isEnabled = allowsScopeSelection
        let formatPopup = ExportPanelSupport.popup(for: ReadingNoteExporter.Format.allCases.map(\.title))
        let savePanel = savePanel(
            documentTitle: documentTitle,
            suffix: fileNameSuffix,
            format: .markdown
        )
        savePanel.accessoryView = accessoryView(
            allowsScopeSelection: allowsScopeSelection,
            scopePopup: scopePopup,
            formatPopup: formatPopup
        )
        savePanel.beginSheetModal(for: parent ?? NSWindow()) { response in
            guard response == .OK, let url = savePanel.url else { return }
            let formatIndex = ExportPanelSupport.selectedIndex(
                from: formatPopup,
                count: ReadingNoteExporter.Format.allCases.count
            )
            let scopeIndex = ExportPanelSupport.selectedIndex(
                from: scopePopup,
                count: ReadingNoteExporter.Scope.allCases.count
            )
            let request = Request(
                format: ReadingNoteExporter.Format.allCases[safe: formatIndex] ?? .markdown,
                scope: allowsScopeSelection
                    ? (ReadingNoteExporter.Scope.allCases[safe: scopeIndex] ?? .all)
                    : .all
            )
            let exportNotes = request.scope.filter(notes)
            guard !exportNotes.isEmpty else {
                self.showNoNotesAlert(scope: request.scope)
                return
            }
            do {
                try Self.write(
                    notes: exportNotes,
                    documentTitle: documentTitle,
                    request: request,
                    to: Self.url(url, matching: request.format)
                )
            } catch {
                let alert = NSAlert(error: error)
                alert.applyLeafStyle()
                alert.runModal()
            }
        }
    }

    func showNoNotesAlert(scope: ReadingNoteExporter.Scope) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("没有可导出的笔记", "No notes to export")
        alert.informativeText = AppText.localized("当前范围“\(scope.title)”里没有阅读笔记。", "There are no reading notes in \(scope.title).")
        alert.addButton(withTitle: AppText.confirm)
        alert.applyLeafStyle()
        alert.runModal()
    }

    private func savePanel(documentTitle: String, suffix: String, format: ReadingNoteExporter.Format) -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = ExportPanelSupport.contentTypes(for: Self.formatOptions())
        savePanel.nameFieldStringValue = Self.fileName(
            documentTitle: documentTitle,
            suffix: suffix,
            format: format
        )
        return savePanel
    }

    private func accessoryView(
        allowsScopeSelection: Bool,
        scopePopup: NSPopUpButton,
        formatPopup: NSPopUpButton
    ) -> NSView {
        let formatRow = (title: AppText.localized("文件类型：", "File type:"), control: formatPopup)
        if allowsScopeSelection {
            return ExportPanelSupport.accessoryView(rows: [
                (title: AppText.localized("范围：", "Scope:"), control: scopePopup),
                formatRow
            ])
        }
        return ExportPanelSupport.accessoryView(rows: [formatRow])
    }

    private static func fileName(
        documentTitle: String,
        suffix: String,
        format: ReadingNoteExporter.Format
    ) -> String {
        "\(VocabularyExporter.safeFileName(documentTitle))-\(suffix).\(format.fileExtension)"
    }

    private static func url(_ url: URL, matching format: ReadingNoteExporter.Format) -> URL {
        ExportPanelSupport.outputURL(url, matching: formatOption(for: format))
    }

    private static func formatOptions() -> [ExportPanelSupport.FormatOption] {
        ReadingNoteExporter.Format.allCases.map(formatOption)
    }

    private static func formatOption(for format: ReadingNoteExporter.Format) -> ExportPanelSupport.FormatOption {
        ExportPanelSupport.FormatOption(title: format.title, fileExtension: format.fileExtension)
    }

    private static func write(
        notes: [ReadingNote],
        documentTitle: String,
        request: Request,
        to url: URL
    ) throws {
        switch request.format {
        case .markdown, .html:
            let output = ReadingNoteExporter.output(
                format: request.format,
                documentTitle: documentTitle,
                notes: notes
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            let html = ReadingNoteExporter.html(
                documentTitle: documentTitle,
                notes: notes
            )
            let data = try ReadingNotePDFExporter.data(html: html)
            try data.write(to: url, options: .atomic)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
