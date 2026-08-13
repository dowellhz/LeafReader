import Cocoa
import PDFKit

extension ReaderWindowController {
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
            ensurePDFTextSnapshotAsync(for: url) { [weak self] snapshot in
                guard let self,
                      self.documentAgentIndexGeneration == generation,
                      self.currentFileURL == url else {
                    return
                }
                let cancellationToken = PDFDocumentTextCancellationToken()
                self.documentAgentIndexCancellationToken = cancellationToken
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    autoreleasepool {
                        let index: PDFDocumentAgentIndex?
                        if let snapshot {
                            index = PDFDocumentAgentIndex(
                                snapshot: snapshot,
                                title: title,
                                cancellationToken: cancellationToken
                            )
                        } else {
                            let document = PDFDocument(url: url)
                            index = document.map { PDFDocumentAgentIndex(document: $0, title: title) }
                        }
                        DispatchQueue.main.async {
                            self?.finishDocumentAgentIndexBuild(index, generation: generation)
                        }
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
        documentAgentIndexCancellationToken = nil
        pdfAgentIndex = index
        isBuildingDocumentAgentIndex = false
        let callbacks = pendingDocumentAgentIndexCallbacks
        pendingDocumentAgentIndexCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    func invalidateDocumentAgentIndex() {
        documentAgentIndexCancellationToken?.cancel()
        documentAgentIndexCancellationToken = nil
        pdfAgentIndex = nil
        isBuildingDocumentAgentIndex = false
        documentAgentIndexGeneration += 1
        pendingDocumentAgentIndexCallbacks.removeAll()
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
