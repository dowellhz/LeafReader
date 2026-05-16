import Cocoa
import PDFKit

final class EdgePagingPDFView: PDFView {
    enum ScrollPageDirection: Equatable {
        case previous
        case next
    }

    var onScrollPastPageEdge: ((ScrollPageDirection) -> Void)?
    var onDroppedDocumentURL: ((URL) -> Void)?

    private var accumulatedEdgeScroll: CGFloat = 0
    private var lastEdgePageTurn = Date.distantPast

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ReaderFileDrop.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ReaderFileDrop.perform(sender) { [weak self] url in
            self?.onDroppedDocumentURL?(url)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            accumulatedEdgeScroll = 0
        }

        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX), abs(deltaY) > 0 else {
            accumulatedEdgeScroll = 0
            super.scrollWheel(with: event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            super.scrollWheel(with: event)
            return
        }

        super.scrollWheel(with: event)

        let direction: ScrollPageDirection?
        if deltaY > 0, isScrolledToBottom {
            direction = .next
        } else if deltaY < 0, isScrolledToTop {
            direction = .previous
        } else {
            accumulatedEdgeScroll = 0
            direction = nil
        }

        guard let direction else { return }
        accumulatedEdgeScroll += abs(deltaY)
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 10 : 1
        guard accumulatedEdgeScroll >= threshold else { return }

        accumulatedEdgeScroll = 0
        turnPage(direction)
    }

    private func turnPage(_ direction: ScrollPageDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastEdgePageTurn) > 0.35 else { return }
        lastEdgePageTurn = now
        onScrollPastPageEdge?(direction)
    }

    private var isScrolledToTop: Bool {
        guard let scrollView = pdfScrollView else { return false }
        return scrollView.contentView.bounds.minY <= 2
    }

    private var isScrolledToBottom: Bool {
        guard let scrollView = pdfScrollView else { return false }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return true }
        let clipHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        guard documentHeight > clipHeight + 2 else { return true }
        return clipView.bounds.maxY >= documentHeight - 2
    }

    private var pdfScrollView: NSScrollView? {
        if let scrollView = enclosingScrollView {
            return scrollView
        }
        return firstScrollView(in: self)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}
