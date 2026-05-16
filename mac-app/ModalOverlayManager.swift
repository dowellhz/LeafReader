import Cocoa

private final class ModalBlockerView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
    }
}

final class ModalOverlayManager {
    static let shared = ModalOverlayManager()

    private struct OverlayEntry {
        let blocker: NSView
        var count: Int
    }

    private var overlays: [ObjectIdentifier: OverlayEntry] = [:]

    private init() {}

    func present(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        if let parent {
            installBlockerIfNeeded(on: parent)
            center(panel, attachedTo: parent)
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    func dismiss(_ panel: NSWindow, attachedTo parent: NSWindow?) {
        if let parent {
            parent.removeChildWindow(panel)
            removeBlockerIfNeeded(from: parent)
        }
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }

    func reactivate(_ panel: NSWindow) {
        guard panel.isVisible else { return }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func installBlockerIfNeeded(on window: NSWindow) {
        let key = ObjectIdentifier(window)
        if var entry = overlays[key] {
            entry.count += 1
            overlays[key] = entry
            entry.blocker.isHidden = false
            return
        }
        guard let contentView = window.contentView else { return }
        let blocker = ModalBlockerView(frame: contentView.bounds)
        blocker.wantsLayer = true
        blocker.layer?.backgroundColor = NSColor.clear.cgColor
        blocker.autoresizingMask = [.width, .height]
        contentView.addSubview(blocker, positioned: .above, relativeTo: nil)
        overlays[key] = OverlayEntry(blocker: blocker, count: 1)
    }

    private func removeBlockerIfNeeded(from window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard var entry = overlays[key] else { return }
        entry.count -= 1
        if entry.count <= 0 {
            entry.blocker.removeFromSuperview()
            overlays.removeValue(forKey: key)
        } else {
            overlays[key] = entry
        }
    }

    private func center(_ panel: NSWindow, attachedTo parent: NSWindow) {
        let parentFrame = parent.frame
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let origin = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(clampedOrigin(origin, panelSize: panel.frame.size, visibleFrame: visibleFrame))
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect?) -> NSPoint {
        guard let visibleFrame else { return origin }
        let minX = visibleFrame.minX + 12
        let maxX = visibleFrame.maxX - panelSize.width - 12
        let minY = visibleFrame.minY + 12
        let maxY = visibleFrame.maxY - panelSize.height - 12
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}
