import Cocoa
import PDFKit

extension ReaderWindowController {
    func schedulePDFTOCBuild(for url: URL, displayBox: PDFDisplayBox) {
        pdfTOCGeneration += 1
        pendingPDFTOCBuildRequest = (url, displayBox)
    }

    func startPendingPDFTOCBuildIfNeeded() {
        guard let request = pendingPDFTOCBuildRequest else { return }
        pendingPDFTOCBuildRequest = nil
        let generation = pdfTOCGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let document = PDFDocument(url: request.url) else { return }
            let toc = ReaderTOCHelper.pdfTOCItems(from: document, displayBox: request.displayBox)
            DispatchQueue.main.async {
                guard let self,
                      self.pdfTOCGeneration == generation,
                      self.currentFileURL?.standardizedFileURL == request.url.standardizedFileURL else {
                    return
                }
                self.currentTOCItems = toc.items
                self.pdfTOCDestinations = toc.destinations
            }
        }
    }

    @objc func showTableOfContents() {
        guard !currentTOCItems.isEmpty else {
            NSSound.beep()
            return
        }

        let menu = NSMenu()
        for (index, item) in currentTOCItems.prefix(120).enumerated() {
            let indent = String(repeating: "  ", count: min(item.level, 4))
            let menuItem = NSMenuItem(title: "\(indent)\(item.title)", action: #selector(selectTableOfContentsItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = index
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: tocButton.bounds.height + 4), in: tocButton)
    }

    @objc func selectTableOfContentsItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, currentTOCItems.indices.contains(index) else { return }
        let item = currentTOCItems[index]
        if currentDocumentKind == .pdf {
            jumpToPDFTOCItem(item)
        } else {
            jumpToWebTOCItem(item)
        }
    }

    func jumpToPDFTOCItem(_ item: ReaderTOCItem) {
        guard let tocDestination = pdfTOCDestinations[item.href],
              let page = pdfView.document?.page(at: tocDestination.pageIndex) else {
            return
        }

        clearAISelectionForNavigation()
        let destination = PDFDestination(page: page, at: tocDestination.point)
        pdfView.go(to: destination)
        lastPageIndex = tocDestination.pageIndex
        updatePageLabel()
        saveSession()
    }

    func jumpToWebTOCItem(_ item: ReaderTOCItem) {
        webView.evaluateJavaScript(ReaderTOCHelper.webJumpScript(for: item))
    }
}
