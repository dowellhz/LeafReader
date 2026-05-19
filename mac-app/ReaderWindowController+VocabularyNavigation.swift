import Cocoa
import PDFKit

extension ReaderWindowController {
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
