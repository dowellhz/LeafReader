import Foundation

extension ReaderWindowController {
    func preparePDFTextSnapshotAsync(for url: URL) {
        ensurePDFTextSnapshotAsync(for: url) { _ in }
    }

    func ensurePDFTextSnapshotAsync(
        for url: URL,
        completion: @escaping (PDFDocumentTextSnapshot?) -> Void
    ) {
        if let snapshot = pdfTextSnapshot {
            completion(snapshot)
            return
        }
        pdfTextSnapshotCallbacks.append(completion)
        guard !isPreparingPDFTextSnapshot else { return }

        isPreparingPDFTextSnapshot = true
        let generation = pdfTextSnapshotGeneration
        let documentID = currentFileMD5
        let token = PDFDocumentTextCancellationToken()
        pdfTextSnapshotCancellationToken = token
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot: PDFDocumentTextSnapshot?
            do {
                snapshot = try PDFDocumentTextSnapshotCache.loadOrCreate(
                    url: url,
                    cancellationToken: token
                )
            } catch {
                snapshot = nil
                if !(error is CancellationError) {
                    NSLog("LeafReader PDF text snapshot failed (error=%@)", error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                guard let self,
                      self.pdfTextSnapshotGeneration == generation,
                      self.currentFileMD5 == documentID else {
                    return
                }
                self.pdfTextSnapshotCancellationToken = nil
                self.isPreparingPDFTextSnapshot = false
                self.pdfTextSnapshot = snapshot
                let callbacks = self.pdfTextSnapshotCallbacks
                self.pdfTextSnapshotCallbacks.removeAll()
                callbacks.forEach { $0(snapshot) }
            }
        }
    }

    func resetPDFTextSnapshotState() {
        pdfTextSnapshotCancellationToken?.cancel()
        pdfTextSnapshotCancellationToken = nil
        pdfTextSnapshotGeneration += 1
        pdfTextSnapshot = nil
        isPreparingPDFTextSnapshot = false
        pdfTextSnapshotCallbacks.removeAll()
    }
}
