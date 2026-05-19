import Cocoa
import PDFKit

extension ReaderWindowController {
    func clearCurrentBookWordRecords() {
        if currentDocumentKind == .pdf {
            clearCurrentPDFWordRecords()
        } else {
            clearCurrentWebWordRecords()
        }
        aiPanel.loadLinkedWordBubbles([])
    }

    func clearCurrentPDFWordRecords() {
        guard !storedWordRecords.isEmpty else { return }
        for record in storedWordRecords {
            guard let page = pdfView.document?.page(at: record.pageIndex) else { continue }
            for annotation in page.annotations where storedWordID(from: annotation) == record.id {
                page.removeAnnotation(annotation)
            }
        }
        storedWordRecords.removeAll()
        highlightedSelectionKeys.removeAll()
        saveStoredWordRecords()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func clearCurrentWebWordRecords() {
        guard !storedWebWordRecords.isEmpty else { return }
        storedWebWordRecords.removeAll()
        saveStoredWebWordRecords()
        let script = """
        (() => {
          document.querySelectorAll('span.leaf-reader-linked-word').forEach((span) => {
            const parent = span.parentNode;
            if (!parent) return;
            while (span.firstChild) parent.insertBefore(span.firstChild, span);
            parent.removeChild(span);
            parent.normalize();
          });
        })();
        """
        webView.evaluateJavaScript(script)
    }

    func storedWordID(at event: NSEvent) -> String? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)

        let wordAnnotation = page.annotations
            .first { annotation in
                annotation.bounds.contains(pointOnPage) && storedWordID(from: annotation) != nil
            }
        if let wordID = wordAnnotation.flatMap(storedWordID(from:)) {
            return wordID
        }

        if let annotation = page.annotation(at: pointOnPage),
           let id = storedWordID(from: annotation) {
            return id
        }
        return nil
    }

    func storedWordID(from annotation: PDFAnnotation) -> String? {
        guard let contents = annotation.contents,
              contents.hasPrefix("leaf-word:") else {
            return nil
        }
        return String(contents.dropFirst("leaf-word:".count))
    }
}
