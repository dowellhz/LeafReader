import Cocoa
import PDFKit

extension ReaderWindowController {
    func autoScrollAIPanelToReadAloudSource(text: String, pageIndex: Int?, pdfBounds: CGRect?) {
        autoScrollAIPanelToReadAloudSource(text: text, pageIndex: pageIndex, pdfBounds: pdfBounds, webProgress: nil)
    }

    func autoScrollAIPanelToReadAloudWebSource(key: String?, text: String, progress: Double?) {
        if let key,
           let source = webAISourceLocationsByKey[key],
           source != lastReadAloudAISource {
            handleReadAloudAISource(source)
            return
        }
        autoScrollAIPanelToReadAloudSource(text: text, pageIndex: nil, pdfBounds: nil, webProgress: progress)
    }

    @discardableResult
    func autoScrollAIPanelToReadAloudLinkedWords(ids: [String], text: String, pageIndex: Int?, pdfBounds: CGRect?) -> Bool {
        let linkedIDs = readAloudLinkedWordIDs(ids: ids, text: text, pageIndex: pageIndex, pdfBounds: pdfBounds)
        guard !linkedIDs.isEmpty else { return false }

        if isAIPanelCollapsed {
            showReadAloudSoftHint(
                key: readAloudLinkedWordsHintKey(ids: linkedIDs),
                title: readAloudLinkedWordsHintTitle(count: linkedIDs.count)
            ) { [weak self] in
                _ = self?.focusReadAloudLinkedWords(linkedIDs)
            }
            return true
        }
        return focusReadAloudLinkedWords(linkedIDs)
    }

    func autoScrollAIPanelToReadAloudSource(text: String, pageIndex: Int?, pdfBounds: CGRect?, webProgress: Double?) {
        guard let source = readAloudAISourceMatcher().readAloudSource(
            matching: text,
            pageIndex: pageIndex,
            pdfBounds: pdfBounds,
            webProgress: webProgress
        ) else {
            return
        }
        handleReadAloudAISource(source)
    }

    private func focusReadAloudLinkedWords(_ linkedIDs: [String]) -> Bool {
        var didLoadAny = false
        var scrollTarget: String?
        for id in linkedIDs {
            guard ensureLinkedWordBubbleLoaded(linkID: id) else { continue }
            didLoadAny = true
            if scrollTarget == nil, id != lastReadAloudLinkedWordID {
                scrollTarget = id
            }
        }
        if let scrollTarget {
            lastReadAloudLinkedWordID = scrollTarget
            aiPanel.scrollToLinkedBubble(id: scrollTarget)
        }
        return didLoadAny
    }

    private func handleReadAloudAISource(_ source: AIConversationSourceLocation) {
        guard source != lastReadAloudAISource else {
            return
        }
        if isAIPanelCollapsed {
            showReadAloudSoftHint(
                key: readAloudAISourceHintKey(source),
                title: AppText.localized("当前朗读内容有关联 AI 笔记", "This passage has linked AI notes")
            ) { [weak self] in
                self?.scrollAIPanelToReadAloudSource(source)
            }
            return
        }
        scrollAIPanelToReadAloudSource(source)
    }

    private func readAloudLinkedWordIDs(ids: [String], text: String, pageIndex: Int?, pdfBounds: CGRect?) -> [String] {
        var linkedIDs = ids
        func append(_ id: String) {
            guard !id.isEmpty, !linkedIDs.contains(id) else { return }
            linkedIDs.append(id)
        }

        if currentDocumentKind == .pdf,
           let pageIndex,
           let pdfBounds,
           let page = pdfView.document?.page(at: pageIndex) {
            storedWordRecords
                .filter {
                    $0.pageIndex == pageIndex
                        && pdfBounds.insetBy(dx: -4, dy: -4).intersects(displayBounds(for: $0, page: page).insetBy(dx: -4, dy: -4))
                }
                .map(\.id)
                .forEach(append)
        }

        storedWebWordRecords
            .filter { ReaderAISourceMatcher.linkedWordText($0.word, overlapsReadAloudText: text) }
            .map(\.id)
            .forEach(append)

        return linkedIDs
    }

    private func scrollAIPanelToReadAloudSource(_ source: AIConversationSourceLocation) {
        guard source != lastReadAloudAISource else { return }
        lastReadAloudAISource = source
        ensureAIConversationSourceBubbleLoaded(source)
        aiPanel.scrollToConversationSource(source)
    }

    private func readAloudLinkedWordsHintKey(ids: [String]) -> String {
        "linkedWords:" + ids.sorted().joined(separator: ",")
    }

    private func readAloudLinkedWordsHintTitle(count: Int) -> String {
        count > 1
            ? AppText.localized("读到 \(count) 个关联单词", "\(count) linked words in this passage")
            : AppText.localized("当前朗读内容有关联单词", "This passage has a linked word")
    }

    private func readAloudAISourceHintKey(_ source: AIConversationSourceLocation) -> String {
        let text = (source.selectedText ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .prefix(80)
        let progress = source.progress.map { String(format: "%.4f", $0) } ?? "-"
        let boundsCount = source.pdfBounds?.count ?? 0
        return "aiSource:\(source.kind.rawValue):\(source.index):\(progress):\(boundsCount):\(text)"
    }

    private func readAloudAISourceMatcher() -> ReaderAISourceMatcher {
        ReaderAISourceMatcher(
            currentDocumentKind: currentDocumentKind,
            currentWebProgress: webScrollProgress,
            candidates: readAloudAISourceCandidates()
        )
    }

    private func readAloudAISourceCandidates() -> [AIConversationSourceLocation] {
        var sources: [AIConversationSourceLocation] = []
        func append(_ source: AIConversationSourceLocation) {
            guard !sources.contains(source) else { return }
            sources.append(source)
        }
        activeAISourceUnderlines.forEach(append)
        aiSourceLocationsByUnderlineKey.values.forEach(append)
        webAISourceLocationsByKey.values.forEach(append)
        if let conversation = loadedAIConversation ?? aiConversationStore?.load() {
            conversation.bubbles.compactMap(\.sourceLocation).forEach(append)
        }
        return sources
    }

}
