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
        let scopePopup = exportPopup(titles: ReadingNoteExporter.Scope.allCases.map(\.title))
        scopePopup.isEnabled = allowsScopeSelection
        let formatPopup = exportPopup(titles: ReadingNoteExporter.Format.allCases.map(\.title))
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
            let request = Request(
                format: ReadingNoteExporter.Format.allCases[safe: formatPopup.indexOfSelectedItem] ?? .markdown,
                scope: allowsScopeSelection
                    ? (ReadingNoteExporter.Scope.allCases[safe: scopePopup.indexOfSelectedItem] ?? .all)
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
        savePanel.allowedContentTypes = []
        savePanel.nameFieldStringValue = Self.fileName(
            documentTitle: documentTitle,
            suffix: suffix,
            format: format
        )
        return savePanel
    }

    private func exportPopup(titles: [String]) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }

    private func accessoryView(
        allowsScopeSelection: Bool,
        scopePopup: NSPopUpButton,
        formatPopup: NSPopUpButton
    ) -> NSView {
        let rowHeight: CGFloat = 32
        let rowSpacing: CGFloat = 8
        let rows = allowsScopeSelection ? 2 : 1
        let height = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: height))

        let formatRow = accessoryRow(title: AppText.localized("文件类型：", "File type:"), control: formatPopup)
        container.addSubview(formatRow)

        if allowsScopeSelection {
            let scopeRow = accessoryRow(title: AppText.localized("范围：", "Scope:"), control: scopePopup)
            container.addSubview(scopeRow)
            NSLayoutConstraint.activate([
                scopeRow.topAnchor.constraint(equalTo: container.topAnchor),
                scopeRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scopeRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scopeRow.heightAnchor.constraint(equalToConstant: rowHeight),
                formatRow.topAnchor.constraint(equalTo: scopeRow.bottomAnchor, constant: rowSpacing)
            ])
        } else {
            NSLayoutConstraint.activate([
                formatRow.topAnchor.constraint(equalTo: container.topAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            formatRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            formatRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            formatRow.heightAnchor.constraint(equalToConstant: rowHeight)
        ])
        return container
    }

    private func accessoryRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 92),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        return row
    }

    private static func fileName(
        documentTitle: String,
        suffix: String,
        format: ReadingNoteExporter.Format
    ) -> String {
        "\(VocabularyExporter.safeFileName(documentTitle))-\(suffix).\(format.fileExtension)"
    }

    private static func url(_ url: URL, matching format: ReadingNoteExporter.Format) -> URL {
        url.deletingPathExtension().appendingPathExtension(format.fileExtension)
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
