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
            editor.pasteStringFromClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
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
            editor.copySelectionToClipboard()
            return true
        case "x":
            editor.copySelectionToClipboard()
            editor.delete(nil)
            return true
        case "v":
            editor.pasteStringFromClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
