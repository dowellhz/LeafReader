import Cocoa

extension ReadingNotePanelController {
    func save() {
        note.markdown = markdownFromEditor()
        note.updatedAt = Date()
        onSave(note)
    }

    func commitEditorChange() {
        save()
        refreshEditorDerivedState()
    }

    func refreshEditorDerivedState() {
        updateWordCount()
        refreshAIToolbar()
    }

    @objc func saveTapped(_ sender: NSButton) {
        editorState.cancelAutoSave()
        save()
        statusLabel.stringValue = AppText.localized("已保存", "Saved")
    }

    func updateWordCount() {
        let count = textView.string.trimmingCharacters(in: .whitespacesAndNewlines).count
        wordCountLabel.stringValue = AppText.localized("\(count) 字", "\(count) chars")
    }

    func noteLocationText() -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("Page \(first.pageIndex + 1)", "Page \(first.pageIndex + 1)")
        }
        let percent = Int((note.locator.webAnchor?.scrollProgress ?? 0) * 100)
        return AppText.localized("网页位置 \(percent)%", "Web \(percent)%")
    }

    func createdAtText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: note.createdAt)
    }

    func scheduleAutoSave() {
        editorState.cancelAutoSave()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        editorState.autoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @objc func showNotesTapped(_ sender: NSButton) {
        closeAfterExplicitSave()
        onShowNotes()
    }

    @objc func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: note.isFavorite
                ? AppText.localized("取消收藏", "Remove Favorite")
                : AppText.localized("收藏并置顶", "Favorite and Pin"),
            action: #selector(toggleFavoriteTapped(_:))
        ))
        menu.addItem(.separator())
        let templateMenu = NSMenu()
        ReadingNoteTemplate.allCases.forEach { template in
            let item = menuItem(title: template.title, action: #selector(templateMenuItemTapped(_:)))
            item.representedObject = template.rawValue
            templateMenu.addItem(item)
        }
        let templateItem = NSMenuItem(title: AppText.localized("套用模板", "Apply Template"), action: nil, keyEquivalent: "")
        templateItem.submenu = templateMenu
        menu.addItem(templateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: AppText.localized("导出当前笔记...", "Export This Note..."), action: #selector(exportCurrentNoteTapped(_:))))
        menu.addItem(menuItem(title: AppText.localized("复制 Markdown", "Copy Markdown"), action: #selector(copyMarkdownTapped(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: AppText.localized("删除笔记", "Delete Note"), action: #selector(deleteCurrentNoteTapped(_:))))
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func exportCurrentNoteTapped(_ sender: NSMenuItem) {
        save()
        onExportNote(note)
    }

    @objc func copyMarkdownTapped(_ sender: NSMenuItem) {
        save()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.markdown, forType: .string)
        statusLabel.stringValue = AppText.localized("已复制 Markdown", "Markdown copied")
    }

    @objc func toggleFavoriteTapped(_ sender: NSMenuItem) {
        note.isFavorite.toggle()
        save()
        statusLabel.stringValue = note.isFavorite
            ? AppText.localized("已收藏", "Favorited")
            : AppText.localized("已取消收藏", "Favorite removed")
    }

    @objc func templateMenuItemTapped(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let template = ReadingNoteTemplate(rawValue: raw) else { return }
        applyTemplate(template)
    }

    @objc func deleteCurrentNoteTapped(_ sender: NSMenuItem) {
        onDeleteNote(note)
    }

    private func closeAfterExplicitSave() {
        save()
        editorState.savesOnClose = false
        close()
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
