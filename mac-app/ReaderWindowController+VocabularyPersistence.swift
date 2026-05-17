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
        if let existing = webWordRecordStore?.existingRecord(in: storedWebWordRecords, word: word, context: context) {
            return existing.id
        }
        if let reusable = reusableWebWordRecord(for: word) {
            let record = StoredWebWordRecord(
                id: UUID().uuidString,
                word: word,
                context: context,
                scrollProgress: webScrollProgress,
                question: reusable.question,
                answer: reusable.answer,
                createdAt: Date(),
                srs: reusable.srs ?? VocabularySRSState.initial()
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecord(record)
            restoreStoredWebWordHighlights()
            return record.id
        }

        let id = UUID().uuidString
        pendingWebWordRecords[id] = PendingWebWordRecord(
            id: id,
            word: word,
            context: context,
            scrollProgress: webScrollProgress,
            createdAt: Date()
        )
        return id
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

    func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            pendingPDFWordRecords.removeValue(forKey: linkID)
            pendingWebWordRecords.removeValue(forKey: linkID)
            return
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWordRecords[index].question = question
            storedWordRecords[index].answer = trimmedAnswer
            saveStoredWordRecord(storedWordRecords[index])
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            storedWebWordRecords[index].question = question
            storedWebWordRecords[index].answer = trimmedAnswer
            saveStoredWebWordRecord(storedWebWordRecords[index])
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                word: pending.word,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            return
        }

        if let pending = pendingWebWordRecords.removeValue(forKey: linkID) {
            let record = StoredWebWordRecord(
                id: pending.id,
                word: pending.word,
                context: pending.context,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecord(record)
            restoreStoredWebWordHighlights()
        }
    }

    func discardPendingLinkedWord(linkID: String) {
        pendingPDFWordRecords.removeValue(forKey: linkID)
        pendingWebWordRecords.removeValue(forKey: linkID)
    }

    func linkedWordAnswer(for linkID: String) -> String? {
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        return nil
    }

    func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWebWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        for record in storedWordRecords {
            addStoredWordAnnotation(record)
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord) {
        guard let page = pdfView.document?.page(at: record.pageIndex) else { return }
        let key = pdfWordRecordStore?.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            ?? "\(record.pageIndex):\(Int(record.bounds.x.rounded())):\(Int(record.bounds.y.rounded())):\(Int(record.bounds.width.rounded())):\(Int(record.bounds.height.rounded()))"
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: record.bounds.cgRect, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
        annotation.contents = "leaf-word:\(record.id)"
        page.addAnnotation(annotation)
    }

    func restoreStoredWebWordHighlights() {
        guard currentDocumentKind != .pdf, !storedWebWordRecords.isEmpty else { return }
        let payload = storedWebWordRecords.map {
            [
                "id": $0.id,
                "word": $0.word,
                "context": $0.context
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreWordHighlights(\(json));")
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

    func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        pdfWordRecordStore?.load() ?? []
    }

    func saveStoredWordRecords() {
        scheduleStoredWordRecordsSave()
    }

    func saveStoredWordRecord(_ record: StoredPDFWordRecord) {
        if pdfWordRecordStore?.upsert(record) != true {
            saveStoredWordRecords()
        }
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    func saveStoredWebWordRecords() {
        scheduleStoredWebWordRecordsSave()
    }

    func saveStoredWebWordRecord(_ record: StoredWebWordRecord) {
        if webWordRecordStore?.upsert(record) != true {
            saveStoredWebWordRecords()
        }
    }

    func deleteStoredWordRecords(ids: [String]) {
        if pdfWordRecordStore?.delete(ids: ids) != true {
            saveStoredWordRecords()
        }
    }

    func deleteStoredWebWordRecords(ids: [String]) {
        if webWordRecordStore?.delete(ids: ids) != true {
            saveStoredWebWordRecords()
        }
    }

    func scheduleStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWordRecordsSave()
        }
    }

    func scheduleStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWebWordRecordsSave()
        }
    }

    func flushStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.cancel()
        pdfWordRecordStore?.save(storedWordRecords)
    }

    func flushStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.cancel()
        webWordRecordStore?.save(storedWebWordRecords)
    }

    func flushCurrentBookWordRecordSaves() {
        flushStoredWordRecordsSave()
        flushStoredWebWordRecordsSave()
    }

    func storedWordID(at event: NSEvent) -> String? {
        guard currentDocumentKind == .pdf else { return nil }
        let pointInPDFView = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        let pointOnPage = pdfView.convert(pointInPDFView, to: page)

        if let annotation = page.annotation(at: pointOnPage),
           let id = storedWordID(from: annotation) {
            return id
        }

        return page.annotations
            .first { annotation in
                annotation.bounds.contains(pointOnPage) && storedWordID(from: annotation) != nil
            }
            .flatMap(storedWordID(from:))
    }

    func storedWordID(from annotation: PDFAnnotation) -> String? {
        guard let contents = annotation.contents,
              contents.hasPrefix("leaf-word:") else {
            return nil
        }
        return String(contents.dropFirst("leaf-word:".count))
    }

    func jumpToStoredLinkedWord(linkID: String) {
        if linkID.hasPrefix("document-source:") {
            let rawIndex = String(linkID.dropFirst("document-source:".count))
            if let index = Int(rawIndex) {
                jumpToDocumentSource(index: index)
            }
            return
        }
        if linkID.hasPrefix("pdf-page:") {
            let rawPage = String(linkID.dropFirst("pdf-page:".count))
            if let pageIndex = Int(rawPage) {
                jumpToPDFPage(index: pageIndex, skipIfCurrentPage: true)
            }
            return
        }
        if storedWebWordRecords.contains(where: { $0.id == linkID }) {
            jumpToStoredWebWord(linkID: linkID)
            return
        }
        jumpToStoredPDFWord(linkID: linkID)
    }

    func jumpToStoredPDFWord(linkID: String) {
        guard let record = storedWordRecords.first(where: { $0.id == linkID }),
              let page = pdfView.document?.page(at: record.pageIndex) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        let beforePageIndex = currentPageIndex()
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: record.bounds.cgRect.minX, y: record.bounds.cgRect.maxY + 80)
        )
        pdfView.go(to: destination)
        lastPageIndex = record.pageIndex
        updatePageLabel()
        saveSession()
        recordPageJump(source: "word-link", before: beforePageIndex, after: currentPageIndex(), detail: record.word)
    }

    func jumpToStoredWebWord(linkID: String) {
        guard let record = storedWebWordRecords.first(where: { $0.id == linkID }) else { return }
        setAIPanelCollapsed(false, animated: true)
        webView.evaluateJavaScript("window.leafReaderScrollToWord(\(jsStringLiteral(linkID)), \(record.scrollProgress));")
    }

    func selectStoredLinkedWord(linkID: String) {
        guard storedWordRecords.contains(where: { $0.id == linkID })
                || storedWebWordRecords.contains(where: { $0.id == linkID }) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        ensureLinkedWordBubbleLoaded(linkID: linkID)
        aiPanel.scrollToLinkedBubble(id: linkID)
    }

    @discardableResult
    func ensureLinkedWordBubbleLoaded(linkID: String) -> Bool {
        guard !aiPanel.hasLinkedBubble(id: linkID) else { return true }
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            let answer = record.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return false }
            aiPanel.appendLinkedWordBubbleIfNeeded(AIChatPanel.LinkedWordBubble(
                id: record.id,
                word: record.word,
                question: record.question,
                answer: answer
            ))
            return true
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            let answer = record.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return false }
            aiPanel.appendLinkedWordBubbleIfNeeded(AIChatPanel.LinkedWordBubble(
                id: record.id,
                word: record.word,
                question: record.question,
                answer: answer
            ))
            return true
        }
        return false
    }

}
