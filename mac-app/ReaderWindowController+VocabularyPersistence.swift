import Cocoa
import PDFKit

extension ReaderWindowController {
    func persistSelectedWordIfNeeded(_ selection: PDFSelection?, text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              let selection,
              let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }

        let selectionBounds = selection.bounds(for: page)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: selectionBounds,
            queryText: text
        ) ?? selectionBounds.insetBy(dx: -1.5, dy: -1)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pageIndex = document.index(for: page)
        if let existing = pdfWordRecordStore?.existingRecord(in: storedWordRecords, pageIndex: pageIndex, bounds: bounds) {
            return existing.id
        }
        if let reusable = reusablePDFWordRecord(for: text) {
            let record = StoredPDFWordRecord(
                id: UUID().uuidString,
                word: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pageIndex: pageIndex,
                bounds: StoredPDFWordRect(bounds),
                context: contextForCurrentSelection(selectedText: text),
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            return record.id
        }

        let id = UUID().uuidString
        pendingPDFWordRecords[id] = PendingPDFWordRecord(
            id: id,
            word: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            context: contextForCurrentSelection(selectedText: text),
            createdAt: Date()
        )
        return id
    }

    func persistSelectedWebWordIfNeeded(text: String) -> String? {
        guard shouldPersistHighlight(for: text),
              currentDocumentKind != .pdf else {
            return nil
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = currentWebSelectionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pending = existingPendingWebWordRecord(
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: pending.id)
            return pending.id
        }
        if let existing = webWordRecordStore?.existingRecord(
            in: storedWebWordRecords,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex
        ) {
            markCurrentWebSelectionAsStoredWord(id: existing.id)
            return existing.id
        }
        if let reusable = reusableWebWordRecord(for: word) {
            let id = UUID().uuidString
            let record = StoredWebWordRecord(
                id: id,
                word: word,
                context: context,
                occurrenceIndex: currentWebSelectionOccurrenceIndex,
                scrollProgress: webScrollProgress,
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWebWordRecords.append(record)
            markCurrentWebSelectionAsStoredWord(id: id)
            saveStoredWebWordRecord(record)
            return record.id
        }

        let id = UUID().uuidString
        markCurrentWebSelectionAsStoredWord(id: id)
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            occurrenceIndex: currentWebSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress,
            createdAt: Date()
        )
        return id
    }

    func existingPendingWebWordRecord(word: String, context: String, occurrenceIndex: Int?) -> PendingWebWordRecord? {
        let normalizedWord = normalizedWebRecordText(word)
        let normalizedContext = normalizedWebRecordText(context)
        return pendingWebWordRecords.values.first { pending in
            normalizedWebRecordText(pending.word) == normalizedWord
                && normalizedWebRecordText(pending.context) == normalizedContext
                && (pending.occurrenceIndex == occurrenceIndex || pending.occurrenceIndex == nil || occurrenceIndex == nil)
        }
    }

    private func normalizedWebRecordText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func precisePDFSelectionBounds(page: PDFPage, originalBounds: CGRect, queryText: String) -> CGRect? {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 80,
              let pageText = page.string,
              !pageText.isEmpty else {
            return nil
        }

        let candidates = pdfTextRanges(matching: normalizedQuery, in: pageText)
        guard !candidates.isEmpty else { return nil }

        let originalCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        var bestBounds: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for range in candidates {
            guard let candidateSelection = page.selection(for: range) else { continue }
            let candidateBounds = candidateSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
            guard candidateBounds.width > 0, candidateBounds.height > 0 else { continue }

            let intersectsOriginal = originalBounds.insetBy(dx: -8, dy: -6).intersects(candidateBounds)
            let candidateCenter = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
            let distance = hypot(candidateCenter.x - originalCenter.x, candidateCenter.y - originalCenter.y)
            let score = intersectsOriginal ? distance : distance + 10_000
            if score < bestScore {
                bestScore = score
                bestBounds = candidateBounds
            }
        }

        return bestBounds
    }

    func pdfTextRanges(matching query: String, in pageText: String) -> [NSRange] {
        let nsText = pageText as NSString
        let words = query.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: #"\s+"#)
        let pattern: String
        if words.count == 1 {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        } else {
            pattern = #"(?i)(?<![A-Za-z'’-])"# + escaped + #"(?![A-Za-z'’-])"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: pageText, range: NSRange(location: 0, length: nsText.length)).map(\.range)
    }

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
