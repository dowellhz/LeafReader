import Cocoa

final class SettingsTextField: NSTextField {
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

final class VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        return constrained
    }

    override var bounds: NSRect {
        get {
            var current = super.bounds
            current.origin.x = 0
            return current
        }
        set {
            var next = newValue
            next.origin.x = 0
            super.bounds = next
        }
    }
}
