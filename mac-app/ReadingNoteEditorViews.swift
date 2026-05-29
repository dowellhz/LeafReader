import Cocoa

enum ReadingNoteEditingShortcut: String {
    case selectAll = "a"
    case copy = "c"
    case cut = "x"
    case paste = "v"
    case undo = "z"

    static func shortcut(for event: NSEvent) -> ReadingNoteEditingShortcut? {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        return ReadingNoteEditingShortcut(rawValue: key)
    }

    var canForwardToFieldEditor: Bool {
        switch self {
        case .selectAll, .copy, .cut, .paste:
            return true
        case .undo:
            return false
        }
    }
}

final class ReadingNoteTextView: NSTextView {
    var onSelectionChanged: (() -> Void)?
    var onSlashCommand: (() -> Void)?
    var onCommitMarkdownLine: (() -> Void)?
    var onMarkdownPaste: ((NSRange) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseDragged(with event: NSEvent) {}

    override func rightMouseUp(with event: NSEvent) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shortcut = ReadingNoteEditingShortcut.shortcut(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        performEditingShortcut(shortcut, event: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if let shortcut = ReadingNoteEditingShortcut.shortcut(for: event) {
            performEditingShortcut(shortcut, event: event)
            return
        }
        let shouldOpenSlashMenu = isPlainSlashEvent(event)
        let shouldCommitMarkdownLine = isPlainReturnEvent(event)
        super.keyDown(with: event)
        if shouldOpenSlashMenu, cursorIsAfterSlash() {
            DispatchQueue.main.async { [weak self] in
                self?.onSlashCommand?()
            }
        } else if shouldCommitMarkdownLine {
            DispatchQueue.main.async { [weak self] in
                self?.onCommitMarkdownLine?()
            }
        }
    }

    private func performEditingShortcut(_ shortcut: ReadingNoteEditingShortcut, event: NSEvent) {
        switch shortcut {
        case .selectAll:
            selectAll(nil)
        case .copy:
            copy(nil)
        case .cut:
            cut(nil)
        case .paste:
            paste(nil)
        case .undo:
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
        }
    }

    private func isPlainSlashEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && event.charactersIgnoringModifiers == "/"
    }

    private func isPlainReturnEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && (event.keyCode == 36 || event.keyCode == 76)
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        onSelectionChanged?()
    }

    override func paste(_ sender: Any?) {
        let pastedText = NSPasteboard.general.string(forType: .string) ?? ""
        let originalSelection = selectedRange()
        super.paste(sender)
        guard ReadingNoteMarkdownInputPolicy.shouldRenderPastedText(pastedText) else { return }
        let insertedLength = max(0, selectedRange().location - originalSelection.location)
        let insertedRange = NSRange(location: originalSelection.location, length: insertedLength)
        DispatchQueue.main.async { [weak self] in
            self?.onMarkdownPaste?(insertedRange)
        }
    }

    private func cursorIsAfterSlash() -> Bool {
        let nsText = string as NSString
        let location = min(selectedRange().location, nsText.length)
        guard location > 0 else { return false }
        return nsText.substring(with: NSRange(location: location - 1, length: 1)) == "/"
    }
}

final class ReadingNoteAskTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let shortcut = ReadingNoteEditingShortcut.shortcut(for: event),
              shortcut.canForwardToFieldEditor else {
            return super.performKeyEquivalent(with: event)
        }
        switch shortcut {
        case .selectAll:
            currentEditor()?.selectAll(nil)
            return true
        case .copy:
            currentEditor()?.copy(nil)
            return true
        case .cut:
            currentEditor()?.cut(nil)
            return true
        case .paste:
            currentEditor()?.paste(nil)
            return true
        case .undo:
            return super.performKeyEquivalent(with: event)
        }
    }
}

extension NSText {
    func performReadingNoteEditingShortcut(_ shortcut: ReadingNoteEditingShortcut) {
        switch shortcut {
        case .selectAll:
            selectAll(nil)
        case .copy:
            copy(nil)
        case .cut:
            cut(nil)
        case .paste:
            paste(nil)
        case .undo:
            break
        }
    }
}

final class ReadingNoteIconButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}
