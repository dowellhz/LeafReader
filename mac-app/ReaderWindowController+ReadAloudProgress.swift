import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let temporaryReadAloudHighlightColor = NSColor(red: 0.56, green: 0.78, blue: 0.49, alpha: 0.32)

    func installSpeechProgressObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpeechProgress(_:)),
            name: SpeechPlaybackCoordinator.readingSegmentDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleSpeechProgress(_ notification: Notification) {
        let isActive = notification.userInfo?["active"] as? Bool ?? false
        guard isActive else {
            guard !isReadAloudActive else { return }
            restoreTitleAfterSpeechPlayback()
            return
        }

        if readAloudOriginalTitle == nil {
            readAloudOriginalTitle = titleLabel.stringValue
            readAloudOriginalToolTip = titleLabel.toolTip
        }

        let text = notification.userInfo?["text"] as? String ?? ""
        let matchText = notification.userInfo?["matchText"] as? String ?? text
        let index = notification.userInfo?["index"] as? Int
        let pageIndex = notification.userInfo?["pageIndex"] as? Int
        if let pageIndex {
            turnPDFReadAloudPageIfNeeded(to: pageIndex)
        }
        titleLabel.toolTip = text
        updateTemporaryReadAloudUnderline(for: matchText, index: index, pageIndex: pageIndex)
    }

    func restoreTitleAfterSpeechPlayback() {
        clearTemporaryReadAloudUnderline()
        resetReadAloudPDFProgress()
        if let original = readAloudOriginalTitle {
            titleLabel.stringValue = original
            readAloudOriginalTitle = nil
        }
        titleLabel.toolTip = readAloudOriginalToolTip
        readAloudOriginalToolTip = nil
    }

    func resetReadAloudPDFProgress() {
        readAloudPDFPages.removeAll()
        readAloudPDFPageTextCache.removeAll()
        readAloudPDFCandidatePageIndex = 0
        readAloudPDFSearchLocation = 0
        readAloudPageLockedAtTopIndex = nil
    }

    private func updateTemporaryReadAloudUnderline(for text: String, index: Int?, pageIndex: Int?) {
        clearTemporaryReadAloudUnderline()
        if currentDocumentKind == .pdf {
            underlinePDFSegment(text, preferredDocumentPageIndex: pageIndex)
        } else {
            underlineWebSegment(text, index: index)
        }
    }

    func clearTemporaryReadAloudUnderline() {
        for item in temporaryReadAloudUnderlineAnnotations {
            item.page.removeAnnotation(item.annotation)
        }
        temporaryReadAloudUnderlineAnnotations.removeAll()
        guard currentDocumentKind != .pdf, webView?.isHidden == false else { return }
        webView?.evaluateJavaScript("window.leafReaderClearTTSUnderline && window.leafReaderClearTTSUnderline();")
    }

    private func underlinePDFSegment(_ text: String, preferredDocumentPageIndex: Int?) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let preferredDocumentPageIndex,
           let document = pdfView.document,
           preferredDocumentPageIndex >= 0,
           preferredDocumentPageIndex < document.pageCount,
           let page = document.page(at: preferredDocumentPageIndex) {
            let preferredCandidateIndex = readAloudPDFPages.enumerated()
                .first { $0.element === page }?
                .offset ?? readAloudPDFCandidatePageIndex
            if underlinePDFSegment(
                text: query,
                page: page,
                candidatePageIndex: preferredCandidateIndex,
                usesCursor: true
            ) {
                return
            }
        }
        let candidatePages = !readAloudPDFPages.isEmpty
            ? readAloudPDFPages
            : [pdfView.currentPage].compactMap { $0 }
        if underlinePDFSegment(text: query, in: candidatePages, usesCursor: true) {
            return
        }
        _ = underlinePDFSegment(text: query, in: candidatePages, usesCursor: false)
    }

    private func turnPDFReadAloudPageIfNeeded(to pageIndex: Int) {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              currentPageIndex() != pageIndex,
              let page = document.page(at: pageIndex) else {
            return
        }
        let bounds = page.bounds(for: pdfView.displayBox)
        let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
        pdfView.go(to: destination)
        readAloudPageLockedAtTopIndex = pageIndex
        lastPageIndex = pageIndex
        updatePageLabel()
        saveSession()
    }

    private func underlinePDFSegment(text query: String, in candidatePages: [PDFPage], usesCursor: Bool) -> Bool {
        for (pageIndex, page) in candidatePages.enumerated() {
            if underlinePDFSegment(text: query, page: page, candidatePageIndex: pageIndex, usesCursor: usesCursor) {
                return true
            }
        }
        return false
    }

    private func underlinePDFSegment(text query: String, page: PDFPage, candidatePageIndex: Int, usesCursor: Bool) -> Bool {
        if usesCursor, candidatePageIndex < readAloudPDFCandidatePageIndex {
            return false
        }
        let documentPageIndex = pdfView.document?.index(for: page)
        guard let pageText = cachedPDFTextForReadAloud(page: page, documentPageIndex: documentPageIndex),
              let nsRange = ReadAloudTextMatcher.range(
                of: query,
                in: pageText,
                searchRange: usesCursor ? readAloudSearchRange(for: pageText, pageIndex: candidatePageIndex) : nil
              ) else {
            return false
        }
        guard let selection = page.selection(for: nsRange) else {
            return false
        }
        var segmentBounds = CGRect.null
        for lineSelection in selection.selectionsByLine() {
            let bounds = lineSelection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            segmentBounds = segmentBounds.union(bounds)
            let annotation = PDFAnnotation(
                bounds: bounds.insetBy(dx: -1, dy: -1),
                forType: .highlight,
                withProperties: nil
            )
            annotation.color = Self.temporaryReadAloudHighlightColor
            annotation.shouldDisplay = true
            annotation.shouldPrint = false
            page.addAnnotation(annotation)
            temporaryReadAloudUnderlineAnnotations.append((page, annotation))
        }
        if !temporaryReadAloudUnderlineAnnotations.isEmpty {
            pdfView.setNeedsDisplay(pdfView.bounds)
            pdfView.documentView?.setNeedsDisplay(pdfView.documentView?.bounds ?? .zero)
            readAloudPDFCandidatePageIndex = candidatePageIndex
            readAloudPDFSearchLocation = NSMaxRange(nsRange)
            let didScrollLinkedWord = autoScrollAIPanelToReadAloudLinkedWords(
                ids: [],
                text: query,
                pageIndex: documentPageIndex,
                pdfBounds: segmentBounds
            )
            if !didScrollLinkedWord {
                autoScrollAIPanelToReadAloudSource(text: query, pageIndex: documentPageIndex, pdfBounds: segmentBounds)
            }
            if documentPageIndex == readAloudPageLockedAtTopIndex {
                readAloudPageLockedAtTopIndex = nil
            } else {
                scrollPDFSegmentToCenter(page: page, bounds: segmentBounds)
            }
            return true
        }
        return false
    }

    private func cachedPDFTextForReadAloud(page: PDFPage, documentPageIndex: Int?) -> String? {
        if let documentPageIndex,
           documentPageIndex != NSNotFound,
           let cached = readAloudPDFPageTextCache[documentPageIndex] {
            return cached.isEmpty ? page.string : cached
        }
        return page.string
    }

    private func readAloudSearchRange(for pageText: String, pageIndex: Int) -> NSRange {
        let fullRange = NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)
        let start = pageIndex == readAloudPDFCandidatePageIndex ? readAloudPDFSearchLocation : 0
        let location = min(max(0, start), fullRange.length)
        return NSRange(location: location, length: fullRange.length - location)
    }

    private func scrollPDFSegmentToCenter(page: PDFPage, bounds: CGRect) {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        let pageVisibleRect = pdfView.convert(pdfView.bounds, to: page)
        let target = NSPoint(
            x: max(bounds.minX, pageVisibleRect.minX),
            y: bounds.midY + pageVisibleRect.height * 0.5
        )
        pdfView.go(to: PDFDestination(page: page, at: target))
    }

    private func underlineWebSegment(_ text: String, index: Int?) {
        let segmentIndex = index ?? 0
        let script = """
        (() => {
          if (window.leafReaderUnderlineTTS) {
            const result = window.leafReaderUnderlineTTS(\(jsStringLiteral(text)));
            if (result && result.ok) return result;
          }
          return window.leafReaderUnderlineTTSIndex && window.leafReaderUnderlineTTSIndex(\(segmentIndex), \(jsStringLiteral(text)));
        })();
        """
        webView?.evaluateJavaScript(script) { [weak self] value, _ in
            DispatchQueue.main.async {
                let result = value as? [String: Any]
                let wordIDs = result?["wordIDs"] as? [String]
                    ?? (result?["wordID"] as? String).map { [$0] }
                    ?? []
                let didScrollLinkedWord = self?.autoScrollAIPanelToReadAloudLinkedWords(
                    ids: wordIDs,
                    text: text,
                    pageIndex: nil,
                    pdfBounds: nil
                ) ?? false
                guard !didScrollLinkedWord else { return }
                let sourceKey = result?["sourceKey"] as? String
                let progress = result?["progress"] as? Double
                self?.autoScrollAIPanelToReadAloudWebSource(key: sourceKey, text: text, progress: progress)
            }
        }
    }

}
