import Cocoa
import PDFKit

final class ReaderSelectionCoordinator {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func clearForNavigation() {
        owner.clearPDFSelectionState()
        clearWebSelectionState()
        owner.aiPanel.clearSelectedText()
        owner.hideSelectionToolbar()
        clearReaderDocumentSelection()
    }

    func clearForBubbleSelection() {
        owner.clearPDFSelectionState()
        clearWebSelectionState()
        owner.hideSelectionToolbar()
        clearReaderDocumentSelection()
    }

    func handlePDFSelectionChanged() {
        guard owner.currentDocumentKind == .pdf else { return }
        guard Date() >= owner.suppressSearchSelectionForAIUntil else {
            owner.clearSearchSelectionForAI()
            return
        }

        let selection = owner.pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        owner.currentPDFSelectedText = selectedText
        updateAISelection(explicitText: selectedText)

        if selectedText.isEmpty {
            owner.hideSelectionToolbar()
        } else if let selection {
            owner.showSelectionToolbarForPDFSelection(selection, text: selectedText)
        }
    }

    func handleWebSelectionChanged(body: Any) {
        guard Date() >= owner.suppressSearchSelectionForAIUntil else {
            owner.clearSearchSelectionForAI()
            return
        }

        let selection = webSelection(from: body)
        setWebSelection(
            text: selection.text,
            context: selection.context,
            occurrenceIndex: selection.occurrenceIndex,
            rect: selection.rect
        )
        updateAISelection(explicitText: owner.currentWebSelectedText)

        if owner.currentWebSelectedText.isEmpty {
            owner.hideSelectionToolbar()
        } else {
            owner.showSelectionToolbarForWebSelection(
                rect: owner.currentWebSelectionRect,
                text: owner.currentWebSelectedText
            )
        }
    }

    func setWebSelectionFromVisibleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        setWebSelection(
            text: trimmed,
            context: trimmed,
            occurrenceIndex: nil,
            rect: nil
        )
        owner.aiPanel.setSelectedText(owner.currentWebSelectedText)
    }

    private func updateAISelection(explicitText: String) {
        let selectedText = ReaderAIContextResolver(
            explicitSelection: explicitText,
            readAloudSelection: owner.currentReadAloudSelectionTextForAI()
        ).preferredSelectionText
        owner.aiPanel.setSelectedText(selectedText)
    }

    private func clearWebSelectionState() {
        owner.currentWebSelectedText = ""
        owner.currentWebSelectionContext = ""
        owner.currentWebSelectionOccurrenceIndex = nil
        owner.currentWebSelectionRect = nil
    }

    private func clearReaderDocumentSelection() {
        if owner.currentDocumentKind == .pdf {
            owner.pdfView.clearSelection()
        } else {
            owner.clearWebSearchSelection()
        }
    }

    private func setWebSelection(text: String, context: String, occurrenceIndex: Int?, rect: NSRect?) {
        owner.currentWebSelectedText = text.count > 1 ? text : ""
        owner.currentWebSelectionContext = owner.currentWebSelectedText.isEmpty ? "" : context
        owner.currentWebSelectionOccurrenceIndex = owner.currentWebSelectedText.isEmpty ? nil : occurrenceIndex
        owner.currentWebSelectionRect = owner.currentWebSelectedText.isEmpty ? nil : rect
    }

    private func webSelection(from body: Any) -> (text: String, context: String, occurrenceIndex: Int?, rect: NSRect?) {
        if let payload = body as? [String: Any] {
            let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let context = (payload["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (
                text: text,
                context: context,
                occurrenceIndex: payload["occurrenceIndex"] as? Int,
                rect: owner.webSelectionRect(from: payload["rect"])
            )
        }

        let text = (body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (text: text, context: "", occurrenceIndex: nil, rect: nil)
    }
}
