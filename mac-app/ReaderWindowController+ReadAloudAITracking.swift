import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let readAloudAISourceMinimumTextOverlapTokens = 4
    private static let readAloudAISourceWebProgressMatchTolerance = 0.08

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
        let segmentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return }
        guard let source = readAloudAISource(
            matching: segmentText,
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
            .filter { Self.linkedWordText($0.word, overlapsReadAloudText: text) }
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

    private func readAloudAISource(
        matching text: String,
        pageIndex: Int?,
        pdfBounds: CGRect?,
        webProgress: Double?
    ) -> AIConversationSourceLocation? {
        let sources = readAloudAISourceCandidates()
        if currentDocumentKind == .pdf, let pageIndex {
            return readAloudPDFSource(
                in: sources.filter { $0.kind == .pdfPage && $0.index == pageIndex },
                text: text,
                pdfBounds: pdfBounds
            )
        }
        let webSources = sources.filter { $0.kind == .webProgress }
        if let source = webSources.first(where: { Self.aiSourceText($0, overlapsReadAloudText: text) }) {
            return source
        }
        return readAloudWebProgressSource(in: webSources, progress: webProgress)
    }

    private func readAloudPDFSource(
        in sources: [AIConversationSourceLocation],
        text: String,
        pdfBounds: CGRect?
    ) -> AIConversationSourceLocation? {
        if let pdfBounds,
           let source = sources.first(where: { readAloudPDFBounds(pdfBounds, intersects: $0.pdfBounds) }) {
            return source
        }
        if let source = sources.first(where: { Self.aiSourceText($0, overlapsReadAloudText: text) }) {
            return source
        }
        if sources.count == 1 {
            return sources.first
        }
        return sources.first(where: { Self.isPageLevelAISource($0) })
    }

    private func readAloudWebProgressSource(in sources: [AIConversationSourceLocation], progress: Double?) -> AIConversationSourceLocation? {
        let target = progress ?? webScrollProgress
        let candidates = sources.compactMap { source -> (source: AIConversationSourceLocation, distance: Double)? in
            guard let sourceProgress = source.progress else { return nil }
            return (source, abs(sourceProgress - target))
        }
        guard let closest = candidates.min(by: { $0.distance < $1.distance }),
              closest.distance <= Self.readAloudAISourceWebProgressMatchTolerance else {
            return nil
        }
        return closest.source
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

    private func readAloudPDFBounds(_ segmentBounds: CGRect, intersects sourceBounds: [StoredPDFWordRect]?) -> Bool {
        guard !segmentBounds.isNull,
              let sourceBounds,
              !sourceBounds.isEmpty else {
            return false
        }
        let paddedSegment = segmentBounds.insetBy(dx: -4, dy: -4)
        return sourceBounds.contains { rect in
            paddedSegment.intersects(rect.cgRect.insetBy(dx: -4, dy: -4))
        }
    }

    private static func aiSourceText(_ source: AIConversationSourceLocation, overlapsReadAloudText text: String) -> Bool {
        guard let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return false
        }
        let selected = normalizedAISourceMatchText(selectedText)
        let spoken = normalizedAISourceMatchText(text)
        guard !selected.isEmpty, !spoken.isEmpty else { return false }
        if spoken.contains(selected) || selected.contains(spoken) {
            return true
        }
        let selectedTokens = Set(aiSourceMatchTokens(in: selected))
        let spokenTokens = Set(aiSourceMatchTokens(in: spoken))
        guard !selectedTokens.isEmpty, !spokenTokens.isEmpty else { return false }
        let overlap = selectedTokens.intersection(spokenTokens)
        return overlap.count >= min(readAloudAISourceMinimumTextOverlapTokens, selectedTokens.count, spokenTokens.count)
    }

    private static func linkedWordText(_ word: String, overlapsReadAloudText text: String) -> Bool {
        let wordText = normalizedAISourceMatchText(word)
        let spoken = normalizedAISourceMatchText(text)
        guard !wordText.isEmpty, !spoken.isEmpty else { return false }
        return spoken.contains(wordText) || wordText.contains(spoken)
    }

    private static func isPageLevelAISource(_ source: AIConversationSourceLocation) -> Bool {
        let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return selectedText.isEmpty && (source.pdfBounds?.isEmpty ?? true)
    }

    private static func normalizedAISourceMatchText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func aiSourceMatchTokens(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}
