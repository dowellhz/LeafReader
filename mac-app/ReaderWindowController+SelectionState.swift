import Cocoa

extension ReaderWindowController {
    func clearAISelectionForNavigation() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentWebSelectionRect = nil
        aiPanel.clearSelectedText()
        hideSelectionToolbar()

        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
    }

    func clearReaderSelectionForBubbleSelection() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentWebSelectionRect = nil
        hideSelectionToolbar()
        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
    }

    @objc func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }
        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(selectedText)
        if selectedText.isEmpty {
            hideSelectionToolbar()
        } else if let selection {
            showSelectionToolbarForPDFSelection(selection, text: selectedText)
        }
    }
}
