import Cocoa

func applyLeafTextSelectionTheme(to textObj: NSText) {
    guard let textView = textObj as? NSTextView else { return }
    let theme = ReaderTheme.selected
    let accent = theme.strongAccentColor
    textView.insertionPointColor = accent
    textView.selectedTextAttributes = [
        .backgroundColor: accent.withAlphaComponent(theme == .eyeCare ? 0.24 : 0.20),
        .foregroundColor: textView.textColor ?? .labelColor
    ]
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var next = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        next.origin.y += max(0, (rect.height - textSize.height) / 2)
        next.size.height = min(next.height, textSize.height)
        return next
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        applyLeafTextSelectionTheme(to: textObj)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        applyLeafTextSelectionTheme(to: textObj)
    }
}

final class VerticallyCenteredSecureTextFieldCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var next = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        next.origin.y += max(0, (rect.height - textSize.height) / 2)
        next.size.height = min(next.height, textSize.height)
        return next
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        applyLeafTextSelectionTheme(to: textObj)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        applyLeafTextSelectionTheme(to: textObj)
    }
}

final class SettingsTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = VerticallyCenteredTextFieldCell(textCell: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cell = VerticallyCenteredTextFieldCell(textCell: stringValue)
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

    override func textDidBeginEditing(_ notification: Notification) {
        if let editor = currentEditor() {
            applyLeafTextSelectionTheme(to: editor)
        }
        super.textDidBeginEditing(notification)
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

final class NonScrollingSettingsScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
