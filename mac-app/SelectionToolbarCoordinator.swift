import Cocoa

final class SelectionToolbarCoordinator {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func show(
        near sourceRect: NSRect,
        text: String,
        preferredEdge: ReaderWindowController.SelectionToolbarEdge
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            owner.hideSelectionToolbar()
            return
        }
        owner.selectionActionToolbar.applyTheme(ReaderTheme.selected)
        owner.configureSelectionToolbarActions(for: text)
        let size = owner.selectionActionToolbar.preferredSize
        let frame = toolbarFrame(near: sourceRect, size: size, preferredEdge: preferredEdge)
        owner.showSelectionToolbarWindow(frameInContent: frame)
    }

    private func toolbarFrame(
        near sourceRect: NSRect,
        size: CGSize,
        preferredEdge: ReaderWindowController.SelectionToolbarEdge
    ) -> NSRect {
        let readerFrame = owner.pdfContainer.frame
        let minimumX = readerFrame.minX + 12
        let maximumX = max(minimumX, readerFrame.maxX - size.width - 12)
        let centeredX = sourceRect.midX - size.width / 2
        let x = min(max(centeredX, minimumX), maximumX)
        let aboveY = sourceRect.maxY + 10
        let belowY = sourceRect.minY - size.height - 10
        let maximumY = readerFrame.maxY - size.height - 12
        let y: CGFloat
        switch preferredEdge {
        case .above:
            y = aboveY <= maximumY ? aboveY : max(readerFrame.minY + 12, belowY)
        case .below:
            y = belowY >= readerFrame.minY + 12 ? belowY : min(aboveY, maximumY)
        }
        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
