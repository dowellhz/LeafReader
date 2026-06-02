import Cocoa

final class ReadingNoteExportCoordinator {
    struct Request {
        let format: ReadingNoteExporter.Format
        let scope: ReadingNoteExporter.Scope
    }

    struct ExportPackage {
        let notes: [ReadingNote]
        let documentTitle: String
        let request: Request
        let fileNameSuffix: String
    }

    func request(allowsScopeSelection: Bool, parent: NSWindow?) -> Request? {
        let controller = ReadingNoteExportOptionsPanel(allowsScopeSelection: allowsScopeSelection)
        guard let result = controller.runModal(attachedTo: parent) else { return nil }
        return Request(format: result.format, scope: result.scope)
    }

    func beginExport(_ package: ExportPackage, parent: NSWindow?) {
        let savePanel = savePanel(for: package)
        savePanel.beginSheetModal(for: parent ?? NSWindow()) { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try Self.write(package, to: url)
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

    private func savePanel(for package: ExportPackage) -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = Self.fileName(
            documentTitle: package.documentTitle,
            suffix: package.fileNameSuffix,
            format: package.request.format
        )
        return savePanel
    }

    private static func fileName(
        documentTitle: String,
        suffix: String,
        format: ReadingNoteExporter.Format
    ) -> String {
        "\(VocabularyExporter.safeFileName(documentTitle))-\(suffix).\(format.fileExtension)"
    }

    private static func write(_ package: ExportPackage, to url: URL) throws {
        switch package.request.format {
        case .markdown, .html:
            let output = ReadingNoteExporter.output(
                format: package.request.format,
                documentTitle: package.documentTitle,
                notes: package.notes
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            let html = ReadingNoteExporter.html(
                documentTitle: package.documentTitle,
                notes: package.notes
            )
            let data = try ReadingNotePDFExporter.data(html: html)
            try data.write(to: url, options: .atomic)
        }
    }
}
