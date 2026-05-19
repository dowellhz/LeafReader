import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    func contextForCurrentSelection(selectedText: String) -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else { return "" }

        guard currentDocumentKind == .pdf else {
            if !currentWebSelectionContext.isEmpty {
                return ReaderAIContextBuilder.selectedTextContext(
                    selectedText: normalizedSelection,
                    sourceText: currentWebSelectionContext,
                    radius: 40
                )
                    ?? currentWebSelectionContext
            }
            return ReaderAIContextBuilder.selectedTextContext(
                selectedText: normalizedSelection,
                sourceText: currentWebPlainText,
                radius: 40
            ) ?? ""
        }

        if let selection = pdfView.currentSelection,
           let page = selection.pages.first {
            let pageText = page.string ?? ""
            if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: pageText, radius: 20) {
                return context
            }

            let bounds = selection.bounds(for: page)
            let expandedBounds = bounds.insetBy(dx: -120, dy: -36)
            if let nearbyText = page.selection(for: expandedBounds)?.string,
               let context = ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: nearbyText, radius: 20) {
                return context
            }
        }

        let currentPageText = pdfView.currentPage?.string ?? ""
        return ReaderAIContextBuilder.selectedTextContext(selectedText: normalizedSelection, sourceText: currentPageText, radius: 20) ?? ""
    }

    func currentSummaryContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: false) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeWhitespace(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(6000))))
        }
    }

    func currentTranslationContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(9000))))
        }
    }

    func currentReadingQuestionContent(completion: @escaping ((title: String, text: String)?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { snapshot in
            guard let snapshot else {
                completion(nil)
                return
            }
            let text = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(snapshot.readingText)
            completion(text.isEmpty ? nil : (snapshot.currentContentTitle, String(text.prefix(5000))))
        }
    }

    func currentReadingContextSnapshot(
        preserveLineBreaks: Bool,
        completion: @escaping (ReadingContextSnapshot?) -> Void
    ) {
        let title = documentTitleForAI()
        if currentDocumentKind == .pdf {
            let visibleText = preserveLineBreaks
                ? ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFPageTranslationText())
                : ReaderAIContextBuilder.normalizeWhitespace(currentPDFPageSummaryText())
            let nearbyText = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(currentPDFNearbyPagesText())
            let selectedText = (pdfView.currentSelection?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedContext = selectedText.isEmpty ? "" : contextForCurrentSelection(selectedText: selectedText)
            completion(ReadingContextSnapshot(
                title: title,
                documentKind: .pdf,
                locationLabel: currentPDFLocationLabel(),
                visibleText: visibleText,
                nearbyText: nearbyText,
                selectedText: selectedText,
                selectedContext: selectedContext
            ))
            return
        }

        currentWebVisibleText(preserveLineBreaks: preserveLineBreaks) { [weak self] visibleText in
            guard let self else {
                completion(nil)
                return
            }
            let nearbyText = preserveLineBreaks
                ? ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(self.currentWebProgressTextWindow())
                : ReaderAIContextBuilder.normalizeWhitespace(self.currentWebProgressTextWindow())
            let selectedText = self.currentWebSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedContext = selectedText.isEmpty ? "" : self.contextForCurrentSelection(selectedText: selectedText)
            completion(ReadingContextSnapshot(
                title: title,
                documentKind: self.currentDocumentKind,
                locationLabel: self.currentWebLocationLabel(),
                visibleText: visibleText,
                nearbyText: nearbyText,
                selectedText: selectedText,
                selectedContext: selectedContext
            ))
        }
    }

    func currentPDFLocationLabel() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else {
            return ""
        }
        let index = document.index(for: page)
        return AppText.localized("第 \(index + 1) / \(document.pageCount) 页", "Page \(index + 1) / \(document.pageCount)")
    }

    func currentWebLocationLabel() -> String {
        let percent = min(100, max(0, Int(round(webScrollProgress * 100))))
        let kind = currentDocumentKind == .epub ? "EPUB" : "DOCX"
        return AppText.localized("\(kind) 约 \(percent)% 位置", "\(kind) about \(percent)%")
    }

    func combinedReadingContext(base: String, snapshot: ReadingContextSnapshot) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty, trimmedBase != AppText.none {
            parts.append(trimmedBase)
        }
        let snapshotContext = snapshot.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snapshotContext.isEmpty {
            parts.append(snapshotContext)
        }
        return String(parts.joined(separator: "\n\n").suffix(6000))
    }

    func currentPDFNearbyPagesText() -> String {
        guard let document = pdfView.document,
              let currentIndex = currentPageIndex() else { return "" }
        let lower = max(0, currentIndex - 2)
        let upper = min(document.pageCount - 1, currentIndex + 2)
        let parts = (lower...upper).compactMap { index -> String? in
            guard index != currentIndex,
                  let page = document.page(at: index) else { return nil }
            let text = ReaderAIContextBuilder.pdfPageTranslationText(document: document, page: page, title: titleLabel.stringValue)
            let normalized = ReaderAIContextBuilder.normalizeReaderTextPreservingParagraphs(text)
            guard !normalized.isEmpty else { return nil }
            return "[Page \(index + 1)]\n\(String(normalized.prefix(1200)))"
        }
        return parts.joined(separator: "\n\n")
    }

    func currentWebVisibleText(preserveLineBreaks: Bool = false, completion: @escaping (String) -> Void) {
        let script = ReaderAIContextBuilder.visibleWebTextScript(preserveLineBreaks: preserveLineBreaks)
        webView.evaluateJavaScript(script) { value, _ in
            let text = (value as? String) ?? ""
            completion(ReaderAIContextBuilder.normalizeVisibleWebText(text, preserveLineBreaks: preserveLineBreaks))
        }
    }

    func currentWebProgressTextWindow() -> String {
        ReaderAIContextBuilder.webProgressTextWindow(plainText: currentWebPlainText, progress: webScrollProgress)
    }

    func currentPDFPageSummaryText() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return "" }
        return ReaderAIContextBuilder.pdfPageSummaryText(document: document, page: page)
    }

    func currentPDFPageTranslationText() -> String {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return "" }
        return ReaderAIContextBuilder.pdfPageTranslationText(
            document: document,
            page: page,
            title: titleLabel.stringValue
        )
    }
}
