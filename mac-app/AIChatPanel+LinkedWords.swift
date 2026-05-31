import Cocoa

extension AIChatPanel {
    func loadLinkedWordBubbles(_ records: [LinkedWordBubble]) {
        isRestoringSavedConversation = true
        isLoadingLinkedWordBubbles = true
        defer { isRestoringSavedConversation = false }
        defer { isLoadingLinkedWordBubbles = false }

        transcriptStack.arrangedSubviews.forEach { view in
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bubbleMetadataByID.removeAll()
        bubbleBoxByLinkID.removeAll()
        persistentBubbleIDs.removeAll()
        lastNotifiedConversationSources.removeAll()
        selectedLinkID = nil
        conversationContext.reset()

        for record in records.suffix(Self.maxInitialLinkedWordBubbles) {
            appendBubble(role: AppText.userRole, text: vocabularyBubbleTitle(for: record.word), collapsible: false, linkID: record.id)
            appendBubble(role: AppText.aiRole, text: record.answer, collapsible: false, renderMarkdown: true, linkID: record.id)
            recordTranscript(role: AppText.userRole, text: vocabularyBubbleTitle(for: record.word), linkID: record.id)
            recordTranscript(role: AppText.aiRole, text: record.answer, linkID: record.id)
            appendMessage(ChatMessage(role: "user", content: record.question, linkID: record.id))
            appendMessage(ChatMessage(role: "assistant", content: record.answer, linkID: record.id))
        }
    }

    func scrollToLinkedBubble(id: String) {
        guard let box = bubbleBoxByLinkID[id] else { return }
        selectedLinkID = id
        updateLinkedBubbleSelection()
        setContentVisible(true)
        DispatchQueue.main.async { [weak self, weak box] in
            guard let self, let box else { return }
            self.scrollTranscriptToTop(of: box)
        }
    }

    func hasLinkedBubble(id: String) -> Bool {
        bubbleBoxByLinkID[id] != nil
    }

    func appendLinkedWordBubbleIfNeeded(_ record: LinkedWordBubble) {
        guard !hasLinkedBubble(id: record.id) else { return }
        let title = vocabularyBubbleTitle(for: record.word)
        appendBubble(role: AppText.userRole, text: title, collapsible: false, linkID: record.id)
        appendBubble(role: AppText.aiRole, text: record.answer, collapsible: false, renderMarkdown: true, linkID: record.id)
        recordTranscript(role: AppText.userRole, text: title, linkID: record.id)
        recordTranscript(role: AppText.aiRole, text: record.answer, linkID: record.id)
    }

    func appendReferenceBubbles(_ records: [LinkedWordBubble]) {
        guard !records.isEmpty else { return }
        for record in records {
            appendBubble(
                role: AppText.localized("依据", "Source"),
                text: "\(record.question)\n\(record.answer)",
                collapsible: false,
                renderMarkdown: false,
                linkID: record.id
            )
        }
    }

    func removeLinkedWordBubbles(ids: [String]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }
        for view in transcriptStack.arrangedSubviews {
            guard let box = view as? ChatBubbleView,
                  let linkID = box.identifier?.rawValue,
                  idSet.contains(linkID) else {
                continue
            }
            for body in box.subviews.compactMap({ $0 as? NSTextField }) {
                if let bodyID = body.identifier?.rawValue {
                    bubbleMetadataByID.removeValue(forKey: bodyID)
                    persistentBubbleIDs.removeAll { $0 == bodyID }
                }
            }
            transcriptStack.removeArrangedSubview(box)
            box.removeFromSuperview()
        }
        for id in idSet {
            bubbleBoxByLinkID.removeValue(forKey: id)
        }
        removeLinkedWordHistory(ids: idSet)
        if let selectedLinkID, idSet.contains(selectedLinkID) {
            self.selectedLinkID = nil
        }
        updateLinkedBubbleSelection()
        notifyConversationChangedIfNeeded()
        transcriptStack.needsLayout = true
        scheduleTranscriptLayout()
    }

    func removeLinkedWordHistory(ids: Set<String>) {
        conversationContext.removeLinkedWordHistory(ids: ids)
    }
}
