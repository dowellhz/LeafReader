import Cocoa

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class APIKeySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "v":
            pasteFromClipboard(into: editor)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func pasteFromClipboard(into editor: NSText) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: text)
    }
}

private final class APIKeyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let editor = currentEditor(),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            editor.selectAll(nil)
            return true
        case "c":
            copySelection(from: editor)
            return true
        case "x":
            copySelection(from: editor)
            editor.delete(nil)
            return true
        case "v":
            pasteFromClipboard(into: editor)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func copySelection(from editor: NSText) {
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
    }

    private func pasteFromClipboard(into editor: NSText) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: text)
    }
}
