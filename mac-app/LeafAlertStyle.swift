import Cocoa

extension NSAlert {
    func applyLeafWhiteStyle() {
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.isOpaque = true
        makeViewTreeWhite(window.contentView)
        if let accessoryView {
            makeViewTreeWhite(accessoryView)
        }
    }

    private func makeViewTreeWhite(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        for subview in view.subviews {
            makeViewTreeWhite(subview)
        }
    }
}
