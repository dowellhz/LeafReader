import Cocoa

final class ReadingNoteExportOptionsPanel: NSWindowController {
    struct Result {
        let format: ReadingNoteExporter.Format
        let scope: ReadingNoteExporter.Scope
    }

    private let allowsScopeSelection: Bool
    private let theme = ReaderTheme.selected
    private let scopePopup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
    private var result: Result?

    init(allowsScopeSelection: Bool) {
        self.allowsScopeSelection = allowsScopeSelection
        let size = NSSize(width: 520, height: allowsScopeSelection ? 320 : 270)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("导出阅读笔记", "Export Reading Notes")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        super.init(window: panel)
        buildContent(in: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func runModal(attachedTo parent: NSWindow?) -> Result? {
        guard let window else { return nil }
        if let parent {
            window.center(relativeTo: parent)
        } else {
            window.center()
        }
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }

    private func buildContent(in panel: NSPanel) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = ReadingNoteTheme.panelBackground(theme).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let title = NSTextField(labelWithString: AppText.localized("导出阅读笔记", "Export Reading Notes"))
        title.font = AppFont.semibold(ofSize: 20)
        title.textColor = ReadingNoteTheme.primaryText(theme)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: AppText.localized("选择导出范围和格式。", "Choose the export scope and format."))
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = ReadingNoteTheme.secondaryText(theme)
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false

        if allowsScopeSelection {
            configurePopup(scopePopup, titles: ReadingNoteExporter.Scope.allCases.map(\.title))
            form.addArrangedSubview(row(title: AppText.localized("范围", "Scope"), control: scopePopup))
        }

        configurePopup(formatPopup, titles: ReadingNoteExporter.Format.allCases.map(\.title))
        form.addArrangedSubview(row(title: AppText.localized("格式", "Format"), control: formatPopup))

        let cancel = NSButton(title: AppText.cancel, target: self, action: #selector(cancelTapped(_:)))
        let export = NSButton(title: AppText.localized("导出", "Export"), target: self, action: #selector(exportTapped(_:)))
        styleActionButton(cancel, primary: false)
        styleActionButton(export, primary: true)
        export.keyEquivalent = "\r"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        export.translatesAutoresizingMaskIntoConstraints = false
        let actions = NSStackView(views: [cancel, export])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, subtitle, form, actions] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 46),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 40),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            form.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 34),
            form.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            form.widthAnchor.constraint(equalToConstant: 370),

            actions.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 34),
            actions.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 142),
            export.widthAnchor.constraint(equalToConstant: 142),
            cancel.heightAnchor.constraint(equalToConstant: 42),
            export.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func row(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = AppFont.semibold(ofSize: 14)
        label.textColor = ReadingNoteTheme.primaryText(theme)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 72),
            control.widthAnchor.constraint(equalToConstant: 284),
            row.heightAnchor.constraint(equalToConstant: 38)
        ])
        return row
    }

    private func configurePopup(_ popup: ThemedSettingsPopUpButton, titles: [String]) {
        popup.theme = theme
        popup.addItems(withTitles: titles)
        popup.font = AppFont.semibold(ofSize: 14)
    }

    private func styleActionButton(_ button: NSButton, primary: Bool) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = primary
            ? ReadingNoteTheme.accent(theme).cgColor
            : ReadingNoteTheme.secondaryButtonBackground(theme).cgColor
        let titleColor: NSColor = primary && theme != .dark ? .white : ReadingNoteTheme.primaryText(theme)
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: titleColor
            ]
        )
    }

    @objc private func exportTapped(_ sender: NSButton) {
        let scope = allowsScopeSelection
            ? ReadingNoteExporter.Scope.allCases[scopePopup.indexOfSelectedItem]
            : .all
        result = Result(
            format: ReadingNoteExporter.Format.allCases[formatPopup.indexOfSelectedItem],
            scope: scope
        )
        if let window {
            NSApp.stopModal()
            window.close()
        }
    }

    @objc private func cancelTapped(_ sender: NSButton) {
        result = nil
        if let window {
            NSApp.stopModal()
            window.close()
        }
    }
}

private extension NSWindow {
    func center(relativeTo parent: NSWindow) {
        let parentFrame = parent.frame
        setFrameOrigin(NSPoint(
            x: parentFrame.midX - frame.width / 2,
            y: parentFrame.midY - frame.height / 2
        ))
    }
}
