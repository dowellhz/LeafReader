import Cocoa
import UniformTypeIdentifiers

extension ReadingNotePanelController {
    @objc func undoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canUndo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.undo()
        commitEditorChange()
    }

    @objc func redoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canRedo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.redo()
        commitEditorChange()
    }

    @objc func boldTapped(_ sender: NSButton) {
        toggleSelectionFontTrait(.boldFontMask)
    }

    @objc func italicTapped(_ sender: NSButton) {
        toggleSelectionFontTrait(.italicFontMask)
    }

    @objc func listTapped(_ sender: NSButton) {
        applyLinePrefix(displayPrefix: "• ")
    }

    @objc func checklistTapped(_ sender: NSButton) {
        applyLinePrefix(displayPrefix: "☐ ")
    }

    @objc func templateTapped(_ sender: NSButton) {
        let menu = NSMenu()
        ReadingNoteTemplate.allCases.forEach { template in
            let item = NSMenuItem(title: template.title, action: #selector(templateMenuItemTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = template.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func imageTapped(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .webP, .heic]
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.insertImage(url: url)
        }
        if let hostWindow = window ?? textView.window ?? rootView.window {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func replaceCurrentSlashLine(with value: String) {
        let lineRange = ReadingNoteSlashRangePolicy.currentLineRange(
            text: textView.string,
            selection: textView.selectedRange()
        )
        let replacement = value + "\n"
        replaceText(in: lineRange, with: replacement)
    }

    func replaceCurrentSlashLineWithEditablePrefix(_ value: String) {
        let lineRange = ReadingNoteSlashRangePolicy.currentLineRange(
            text: textView.string,
            selection: textView.selectedRange()
        )
        replaceText(in: lineRange, with: value)
    }

    func replaceCurrentSlashTrigger(with value: String) {
        guard let trigger = ReadingNoteSlashRangePolicy.trigger(
            text: textView.string,
            selection: textView.selectedRange()
        ) else { return }
        replaceText(in: trigger.triggerRange, with: value)
    }

    func applyTemplate(_ template: ReadingNoteTemplate) {
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            statusLabel.stringValue = AppText.localized("请先配置 API Key", "Configure API Key first")
            NSSound.beep()
            onModelSettingsRequired()
            return
        }
        let templateMarkdown = template.markdown(quote: note.quote)
        runTemplatePolish(template, markdown: templateMarkdown)
    }

    func replaceCurrentSlashLineWithMarkdownBlock(_ block: MarkdownRenderer.Block) {
        let lineRange = ReadingNoteSlashRangePolicy.currentLineRange(
            text: textView.string,
            selection: textView.selectedRange()
        )
        let attributes = markdownTypingAttributes(for: block)
        guard textView.shouldChangeText(in: lineRange, replacementString: "") else { return }
        textView.textStorage?.replaceCharacters(in: lineRange, with: NSAttributedString(string: "", attributes: attributes))
        textView.typingAttributes = attributes
        textView.didChangeText()
        textView.setSelectedRange(boundedSelectionRange(location: lineRange.location, length: 0))
        commitEditorChange()
    }

    func resetMarkdownTypingAttributes() {
        textView.typingAttributes = ReadingNoteEditorRenderer.paragraphTypingAttributes(theme: ReaderTheme.selected)
    }

    private func markdownTypingAttributes(for block: MarkdownRenderer.Block) -> [NSAttributedString.Key: Any] {
        ReadingNoteEditorRenderer.typingAttributes(for: block, theme: ReaderTheme.selected)
    }

    func replaceSelectedText(in range: NSRange, with value: String) {
        guard range.length > 0 else { return }
        replaceText(in: boundedSelectionRange(location: range.location, length: range.length), with: value)
    }

    func replaceSelectedText(in range: NSRange, with value: NSAttributedString) {
        guard range.length > 0 else { return }
        replaceText(in: boundedSelectionRange(location: range.location, length: range.length), with: value)
    }

    func replaceText(
        in range: NSRange,
        with value: String,
        selection: ReadingNoteTextReplacementPolicy.Selection = .caretAfterReplacement
    ) {
        guard textView.shouldChangeText(in: range, replacementString: value) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        restoreSelection(afterReplacing: range, replacementLength: (value as NSString).length, selection: selection)
        commitEditorChange()
    }

    func replaceText(
        in range: NSRange,
        with value: NSAttributedString,
        selection: ReadingNoteTextReplacementPolicy.Selection = .caretAfterReplacement
    ) {
        guard textView.shouldChangeText(in: range, replacementString: value.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        restoreSelection(afterReplacing: range, replacementLength: value.length, selection: selection)
        commitEditorChange()
    }

    private func restoreSelection(
        afterReplacing range: NSRange,
        replacementLength: Int,
        selection: ReadingNoteTextReplacementPolicy.Selection
    ) {
        let textLength = (textView.string as NSString).length
        let restored = ReadingNoteTextReplacementPolicy.selectionRange(
            replacing: range,
            replacementLength: replacementLength,
            textLengthAfterReplacement: textLength,
            selection: selection
        )
        textView.setSelectedRange(restored)
    }

    private func toggleSelectionFontTrait(_ trait: NSFontTraitMask) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            NSSound.beep()
            return
        }
        guard let selected = textView.textStorage?.attributedSubstring(from: range) else { return }
        let toggled = ReadingNoteInlineStylePolicy.toggled(
            attributed: selected,
            trait: trait,
            defaultFont: ReadingNoteEditorRenderer.defaultEditorFont()
        )
        replaceText(in: range, with: toggled, selection: .range(NSRange(location: range.location, length: toggled.length)))
    }

    private func applyLinePrefix(displayPrefix: String) {
        guard let replacement = ReadingNoteLinePrefixPolicy.replacement(
            text: textView.string,
            selection: textView.selectedRange(),
            displayPrefix: displayPrefix
        ) else { return }
        replaceText(
            in: replacement.range,
            with: replacement.text,
            selection: .range(replacement.selection)
        )
    }

    private func boundedSelectionRange(location: Int, length: Int) -> NSRange {
        let textLength = (textView.string as NSString).length
        return ReadingNoteTextReplacementPolicy.boundedRange(location: location, length: length, textLength: textLength)
    }

    private func insertImage(url: URL) {
        guard let assetURL = try? ReadingNoteAssetStore.importImage(from: url),
              NSImage(contentsOf: assetURL) != nil else {
            NSSound.beep()
            return
        }
        let markdown = ReadingNoteDocument.imageMarkdown(url: assetURL, title: url.deletingPathExtension().lastPathComponent)
        let value = NSMutableAttributedString(attributedString: ReadingNoteEditorRenderer.renderMarkdown(
            markdown,
            theme: ReaderTheme.selected
        ))
        if !value.string.hasSuffix("\n") {
            value.append(NSAttributedString(string: "\n"))
        }
        let range = textView.selectedRange()
        replaceText(in: range, with: value)
    }
}
