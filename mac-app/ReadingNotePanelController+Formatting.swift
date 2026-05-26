import Cocoa
import UniformTypeIdentifiers

extension ReadingNotePanelController {
    @objc func undoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canUndo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.undo()
        save()
        updateWordCount()
    }

    @objc func redoTapped(_ sender: NSButton) {
        guard textView.undoManager?.canRedo == true else {
            NSSound.beep()
            return
        }
        textView.undoManager?.redo()
        save()
        updateWordCount()
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

    @objc func imageTapped(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .webP, .heic]
        panel.beginSheetModal(for: window ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.insertImage(url: url)
        }
    }

    func replaceCurrentSlashLine(with value: String) {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let replacement = value + "\n"
        replaceText(in: lineRange, with: replacement)
    }

    func replaceSelectedText(in range: NSRange, with value: String) {
        guard range.length > 0 else { return }
        replaceText(in: boundedSelectionRange(location: range.location, length: range.length), with: value)
    }

    func replaceSelectedText(in range: NSRange, with value: NSAttributedString) {
        guard range.length > 0 else { return }
        replaceText(in: boundedSelectionRange(location: range.location, length: range.length), with: value)
    }

    func replaceText(in range: NSRange, with value: String) {
        guard textView.shouldChangeText(in: range, replacementString: value) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (value as NSString).length, length: 0))
        save()
        updateWordCount()
    }

    func replaceText(in range: NSRange, with value: NSAttributedString) {
        guard textView.shouldChangeText(in: range, replacementString: value.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + value.length, length: 0))
        save()
        updateWordCount()
    }

    private func toggleSelectionFontTrait(_ trait: NSFontTraitMask) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            NSSound.beep()
            return
        }
        guard let selected = textView.textStorage?.attributedSubstring(from: range).mutableCopy() as? NSMutableAttributedString else { return }
        let shouldRemove = selectionContainsTrait(selected, trait: trait)
        let fullRange = NSRange(location: 0, length: selected.length)
        var fontUpdates: [(font: NSFont, range: NSRange)] = []
        selected.enumerateAttribute(.font, in: fullRange) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 15)
            let toggled = shouldRemove
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            fontUpdates.append((toggled, subrange))
        }
        for update in fontUpdates {
            selected.addAttribute(.font, value: update.font, range: update.range)
        }
        replaceText(in: range, with: selected)
        textView.setSelectedRange(NSRange(location: range.location, length: selected.length))
    }

    private func selectionContainsTrait(_ attributed: NSAttributedString, trait: NSFontTraitMask) -> Bool {
        guard attributed.length > 0 else { return false }
        let symbolicTrait: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
        var containsTrait = false
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let font = value as? NSFont else { return }
            if font.fontDescriptor.symbolicTraits.contains(symbolicTrait) {
                containsTrait = true
                stop.pointee = true
            }
        }
        return containsTrait
    }

    private func applyLinePrefix(displayPrefix: String) {
        let selection = textView.selectedRange()
        guard selection.length > 0 else {
            insertListPrefixAtInsertionPoint(displayPrefix)
            return
        }
        let nsText = textView.string as NSString
        let paragraphRange = nsText.paragraphRange(for: selection)
        let selected = nsText.substring(with: paragraphRange) as NSString
        let shouldRemovePrefix = selectionAlreadyUsesPrefix(displayPrefix, in: selected)
        var offset = 0
        let replacement = NSMutableString()
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, enclosingRange, _ in
            let line = selected.substring(with: lineRange)
            let enclosing = selected.substring(with: enclosingRange)
            let newlineSuffix = String(enclosing.dropFirst(line.count))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                replacement.append(line + newlineSuffix)
            } else if shouldRemovePrefix {
                let updated = self.removingLinePrefix(displayPrefix, from: line)
                replacement.append(updated + newlineSuffix)
                offset -= line.count - updated.count
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("☐ ") || trimmed.hasPrefix("☑ ") {
                replacement.append(line + newlineSuffix)
            } else {
                replacement.append(displayPrefix + line + newlineSuffix)
                offset += displayPrefix.count
            }
        }
        let oldLocation = selection.location
        let oldEnd = selection.location + selection.length
        replaceText(in: paragraphRange, with: replacement as String)
        let newLocation = oldLocation + (oldLocation == paragraphRange.location ? 0 : displayPrefix.count)
        let newLength = max(0, oldEnd - oldLocation + offset)
        textView.setSelectedRange(boundedSelectionRange(location: newLocation, length: newLength))
    }

    private func selectionAlreadyUsesPrefix(_ displayPrefix: String, in selected: NSString) -> Bool {
        selectedNonEmptyLines(in: selected).allSatisfy { lineHasPrefix(displayPrefix, $0) }
    }

    private func selectedNonEmptyLines(in selected: NSString) -> [String] {
        var lines: [String] = []
        selected.enumerateSubstrings(
            in: NSRange(location: 0, length: selected.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = selected.substring(with: lineRange)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    private func lineHasPrefix(_ displayPrefix: String, _ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(displayPrefix)
    }

    private func removingLinePrefix(_ displayPrefix: String, from line: String) -> String {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let remainder = line.dropFirst(leadingWhitespace.count)
        guard remainder.hasPrefix(displayPrefix) else { return line }
        return String(leadingWhitespace) + String(remainder.dropFirst(displayPrefix.count))
    }

    private func boundedSelectionRange(location: Int, length: Int) -> NSRange {
        let textLength = (textView.string as NSString).length
        let boundedLocation = min(max(0, location), textLength)
        let boundedLength = min(max(0, length), textLength - boundedLocation)
        return NSRange(location: boundedLocation, length: boundedLength)
    }

    private func insertListPrefixAtInsertionPoint(_ displayPrefix: String) {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        let insertPrefix = location == 0 || nsText.substring(to: location).hasSuffix("\n") ? "" : "\n"
        insertTextAtSelection(insertPrefix + displayPrefix)
    }

    private func insertTextAtSelection(_ value: String) {
        let range = textView.selectedRange()
        replaceText(in: range, with: value)
    }

    private func insertImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            NSSound.beep()
            return
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = scaledImageBounds(for: image)
        let value = NSMutableAttributedString(attachment: attachment)
        value.addAttribute(.link, value: url.absoluteString, range: NSRange(location: 0, length: value.length))
        value.append(NSAttributedString(string: "\n"))
        let range = textView.selectedRange()
        replaceText(in: range, with: value)
    }

    private func scaledImageBounds(for image: NSImage) -> NSRect {
        let maxWidth: CGFloat = 360
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: -4, width: 180, height: 120)
        }
        let scale = min(1, maxWidth / size.width)
        return NSRect(x: 0, y: -4, width: size.width * scale, height: size.height * scale)
    }
}
