import Cocoa
import PDFKit

extension ReaderWindowController {
    func ensureDocumentAgentIndex() {
        guard pdfAgentIndex == nil else { return }
        if currentDocumentKind == .pdf {
            guard let document = pdfView.document else { return }
            pdfAgentIndex = PDFDocumentAgentIndex(document: document, title: titleLabel.stringValue)
            return
        }
        guard !currentWebPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pdfAgentIndex = PDFDocumentAgentIndex(text: currentWebPlainText)
    }

    func ensureDocumentAgentIndexAsync(completion: (() -> Void)? = nil) {
        if pdfAgentIndex != nil {
            completion?()
            return
        }
        if let completion {
            pendingDocumentAgentIndexCallbacks.append(completion)
        }
        guard !isBuildingDocumentAgentIndex else { return }

        isBuildingDocumentAgentIndex = true
        let generation = documentAgentIndexGeneration
        let kind = currentDocumentKind
        let title = titleLabel.stringValue

        if kind == .pdf {
            guard let url = currentFileURL else {
                finishDocumentAgentIndexBuild(nil, generation: generation)
                return
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                autoreleasepool {
                    let document = PDFDocument(url: url)
                    let index = document.map { PDFDocumentAgentIndex(document: $0, title: title) }
                    DispatchQueue.main.async {
                        self?.finishDocumentAgentIndexBuild(index, generation: generation)
                    }
                }
            }
            return
        }

        let text = currentWebPlainText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishDocumentAgentIndexBuild(nil, generation: generation)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let index = PDFDocumentAgentIndex(text: text)
            DispatchQueue.main.async {
                self?.finishDocumentAgentIndexBuild(index, generation: generation)
            }
        }
    }

    func finishDocumentAgentIndexBuild(_ index: PDFDocumentAgentIndex?, generation: Int) {
        guard generation == documentAgentIndexGeneration else { return }
        pdfAgentIndex = index
        isBuildingDocumentAgentIndex = false
        let callbacks = pendingDocumentAgentIndexCallbacks
        pendingDocumentAgentIndexCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    func currentEmbeddingPriorityIndex() -> Int? {
        if currentDocumentKind == .pdf {
            return currentPageIndex()
        }
        guard let count = pdfAgentIndex?.locationCount, count > 0 else { return nil }
        let index = Int((Double(count - 1) * min(1, max(0, webScrollProgress))).rounded())
        return min(count - 1, max(0, index))
    }

    func evidenceLocationName() -> String {
        currentDocumentKind == .pdf ? AppText.localized("Page", "Page") : AppText.localized("片段", "Section")
    }
}
