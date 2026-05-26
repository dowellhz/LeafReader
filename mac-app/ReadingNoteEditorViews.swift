import Cocoa

final class ReadingNoteTextView: NSTextView {
    var onSelectionChanged: (() -> Void)?
    var onSlashCommand: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseDragged(with event: NSEvent) {}

    override func rightMouseUp(with event: NSEvent) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        onSelectionChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, currentLineIsSlashCommand() {
            onSlashCommand?()
            return
        }
        super.keyDown(with: event)
    }

    private func currentLineIsSlashCommand() -> Bool {
        let nsText = string as NSString
        let location = min(selectedRange().location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return line == "/"
    }
}

final class ReadingNoteAskTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        case "v":
            currentEditor()?.paste(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

final class ReadingNoteIconButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}
