import Cocoa

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class APIKeySecureTextField: NSSecureTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = VerticallyCenteredSecureTextFieldCell(textCell: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cell = VerticallyCenteredSecureTextFieldCell(textCell: stringValue)
    }

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

    override func textDidBeginEditing(_ notification: Notification) {
        if let editor = currentEditor() {
            applyLeafTextSelectionTheme(to: editor)
        }
        super.textDidBeginEditing(notification)
    }
}
