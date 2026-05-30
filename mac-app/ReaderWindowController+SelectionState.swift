import Cocoa

extension ReaderWindowController {
    func clearAISelectionForNavigation() {
        selectionCoordinator.clearForNavigation()
    }

    func clearReaderSelectionForBubbleSelection() {
        selectionCoordinator.clearForBubbleSelection()
    }

    @objc func selectionChanged() {
        selectionCoordinator.handlePDFSelectionChanged()
    }
}
