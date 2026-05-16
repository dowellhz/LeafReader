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

    func documentAgentPrompt(question: String, context: String, completion: @escaping (String?) -> Void) {
        currentReadingContextSnapshot(preserveLineBreaks: true) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, let snapshot else {
                    completion(nil)
                    return
                }
                if self.currentDocumentKind == .pdf {
                    self.pdfDocumentAgentPrompt(question: question, context: context, snapshot: snapshot, completion: completion)
                    return
                }
                self.webDocumentAgentPrompt(question: question, context: context, snapshot: snapshot, completion: completion)
            }
        }
    }

    func pdfDocumentAgentPrompt(
        question: String,
        context: String,
        snapshot: ReadingContextSnapshot,
        completion: @escaping (String?) -> Void
    ) {
        guard pdfView.document != nil else {
            completion(nil)
            return
        }

        let currentPageText = snapshot.visibleText
        let chapterText = snapshot.nearbyText
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: currentPageText) { [weak self] retrievalQuery in
                DispatchQueue.main.async {
                    guard let self else {
                        completion(nil)
                        return
                    }
                    let combinedRetrievalQuestion = [question, retrievalQuery]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    let retrievalQuestion = combinedRetrievalQuestion.isEmpty ? question : combinedRetrievalQuestion
                    let currentPageIndex = self.currentPageIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: currentPageIndex) { [weak self] in
                        guard let self else {
                            completion(nil)
                            return
                        }
                        self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                            DispatchQueue.main.async {
                                guard let self else {
                                    completion(nil)
                                    return
                                }
                                let evidence = self.pdfAgentIndex?.search(
                                    question: retrievalQuestion,
                                    currentPageIndex: self.currentPageIndex(),
                                    queryEmbedding: queryEmbedding
                                ) ?? []
                                self.appendEvidenceBubbles(evidence)
                                var searchResults = PDFDocumentAgentIndex.evidenceText(evidence, locationName: self.evidenceLocationName())
                                if let coverageText = self.embeddingCoveragePromptText() {
                                    searchResults = searchResults.isEmpty ? coverageText : "\(coverageText)\n\n\(searchResults)"
                                }
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: self.documentTitleForAI(),
                                    question: question,
                                    currentPageText: String(currentPageText.prefix(3500)),
                                    chapterText: String(chapterText.prefix(5000)),
                                    searchResults: searchResults,
                                    context: combinedContext
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    func webDocumentAgentPrompt(
        question: String,
        context: String,
        snapshot: ReadingContextSnapshot,
        completion: @escaping (String?) -> Void
    ) {
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: snapshot.visibleText) { [weak self] retrievalQuery in
                DispatchQueue.main.async {
                    guard let self else {
                        completion(nil)
                        return
                    }
                    let combinedRetrievalQuestion = [question, retrievalQuery]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    let retrievalQuestion = combinedRetrievalQuestion.isEmpty ? question : combinedRetrievalQuestion
                    let priorityIndex = self.currentEmbeddingPriorityIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: priorityIndex) { [weak self] in
                        guard let self else {
                            completion(nil)
                            return
                        }
                        self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                            DispatchQueue.main.async {
                                guard let self else {
                                    completion(nil)
                                    return
                                }
                                let evidence = self.pdfAgentIndex?.search(
                                    question: retrievalQuestion,
                                    currentPageIndex: self.currentEmbeddingPriorityIndex(),
                                    queryEmbedding: queryEmbedding
                                ) ?? []
                                self.appendEvidenceBubbles(evidence)
                                var searchResults = PDFDocumentAgentIndex.evidenceText(evidence, locationName: self.evidenceLocationName())
                                if let coverageText = self.embeddingCoveragePromptText() {
                                    searchResults = searchResults.isEmpty ? coverageText : "\(coverageText)\n\n\(searchResults)"
                                }
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: snapshot.title,
                                    question: question,
                                    currentPageText: String(snapshot.visibleText.prefix(3500)),
                                    chapterText: String(snapshot.nearbyText.prefix(5000)),
                                    searchResults: searchResults,
                                    context: combinedContext,
                                    currentTextTitle: AppText.localized("当前可见内容", "Current visible text"),
                                    nearbyTextTitle: AppText.localized("当前阅读位置附近内容", "Nearby reading text")
                                ))
                            }
                        }
                    }
                }
            }
        }
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

    func appendEvidenceBubbles(_ evidence: [PDFDocumentAgentEvidence]) {
        if evidence.isEmpty {
            aiPanel.appendNotice(AppText.localized("未检索到明确文档依据，将主要结合当前问题和阅读上下文回答。", "No strong document evidence was found; the answer will rely mostly on the question and reading context."))
            return
        }
        if let top = evidence.first, top.score < 6 {
            aiPanel.appendNotice(AppText.localized("文档依据较弱，回答会以谨慎判断为主。", "Document evidence is weak; the answer will be cautious."))
        }
        let bubbles = evidence.prefix(4).map { item in
            let label = currentDocumentKind == .pdf
                ? AppText.localized("第 \(item.pageNumber) 页", "Page \(item.pageNumber)")
                : AppText.localized("片段 \(item.pageNumber)", "Section \(item.pageNumber)")
            return AIChatPanel.LinkedWordBubble(
                id: "document-source:\(item.pageIndex)",
                word: label,
                question: AppText.localized("检索依据 \(label)", "Source \(label)"),
                answer: String(item.text.prefix(500))
            )
        }
        aiPanel.appendReferenceBubbles(bubbles)
    }

    func documentTitleForAI() -> String {
        var title = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let removableSuffixes = [
            " - PDF Room",
            "- PDF Room",
            " PDF Room",
            "-Chinese-translated",
            "-translated",
            "_Chinese-translated"
        ]
        for suffix in removableSuffixes where title.localizedCaseInsensitiveContains(suffix) {
            title = title.replacingOccurrences(of: suffix, with: "", options: [.caseInsensitive])
        }
        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_").union(.whitespacesAndNewlines))
        return title.isEmpty ? titleLabel.stringValue : title
    }

    func crossLingualRetrievalQueryIfNeeded(
        question: String,
        currentPageText: String,
        completion: @escaping (String?) -> Void
    ) {
        guard questionLooksMostlyChinese(question),
              textLooksMostlyEnglish(currentPageText),
              AISettingsStore.hasAPIKeyForSelectedModel else {
            completion(nil)
            return
        }

        let prompt = """
        Convert the user's Chinese document-search question into one concise English search query for retrieving passages from an English book.

        Requirements:
        - Output only the English search query.
        - Keep names, places, book-specific terms, and quoted words.
        - Do not answer the question.
        - Do not add explanations.

        Chinese question:
        \(question)
        """
        retrievalQueryClient.send(messages: [
            ChatMessage(role: "system", content: "You create concise English search queries."),
            ChatMessage(role: "user", content: prompt)
        ]) { result in
            if case .success(let text) = result {
                let cleaned = text
                    .replacingOccurrences(of: #"^[\"“”']+|[\"“”']+$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(cleaned.isEmpty ? nil : String(cleaned.prefix(240)))
                return
            }
            completion(nil)
        }
    }

    func questionLooksMostlyChinese(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        return chineseCount >= 2 && chineseCount * 2 >= max(1, letterCount)
    }

    func textLooksMostlyEnglish(_ text: String) -> Bool {
        let sample = String(text.prefix(1200))
        let scalars = sample.unicodeScalars
        let latinCount = scalars.filter {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }.count
        let chineseCount = scalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        return latinCount >= 80 && latinCount > chineseCount * 4
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

    func shouldPersistHighlight(for text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 80 else { return false }
        let words = normalized.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return normalized.range(of: #"^[A-Za-z][A-Za-z'’-]*(\s+[A-Za-z][A-Za-z'’-]*){0,4}$"#, options: .regularExpression) != nil
    }
}
