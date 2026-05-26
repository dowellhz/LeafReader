import Cocoa

final class ClickEditableTextField: NSTextField {
    private var allowsEditingFocus = false

    override var acceptsFirstResponder: Bool {
        allowsEditingFocus || currentEditor() != nil
    }

    override func mouseDown(with event: NSEvent) {
        allowsEditingFocus = true
        defer { allowsEditingFocus = false }
        super.mouseDown(with: event)
    }
}

final class WindowDragTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class WindowDragImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
