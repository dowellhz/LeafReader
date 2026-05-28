import Cocoa

extension AIChatPanel {
    func persistBubbleIfNeeded(_ body: NSTextField?) {
        guard let bodyID = body?.identifier?.rawValue,
              !persistentBubbleIDs.contains(bodyID),
              let metadata = bubbleMetadataByID[bodyID],
              shouldPersistBubble(role: metadata.role, text: metadata.text, linkID: metadata.linkID) else {
            return
        }
        persistentBubbleIDs.append(bodyID)
        trimVisibleNormalConversationBubblesIfNeeded()
        notifyConversationChangedIfNeeded()
    }

    func trimVisibleNormalConversationBubblesIfNeeded() {
        let normalBubbleIDs = persistentBubbleIDs.filter { bodyID in
            guard let metadata = bubbleMetadataByID[bodyID] else { return false }
            return metadata.linkID == nil
        }
        let excessCount = normalBubbleIDs.count - Self.maxVisibleNormalConversationBubbles
        guard excessCount > 0 else { return }

        let activeBodyID = requestState.assistantBody?.identifier?.rawValue
        for bodyID in normalBubbleIDs.prefix(excessCount) where bodyID != activeBodyID {
            removeConversationBubble(bodyID: bodyID)
        }
    }

    func removeConversationBubble(bodyID: String) {
        guard let metadata = bubbleMetadataByID[bodyID],
              metadata.linkID == nil else { return }
        removeBubbleView(bodyID: bodyID)
        bubbleMetadataByID.removeValue(forKey: bodyID)
        persistentBubbleIDs.removeAll { $0 == bodyID }
        notifyConversationChangedIfNeeded()
    }

    @objc func deleteBubble(_ sender: NSButton) {
        guard let bodyID = sender.identifier?.rawValue,
              let metadata = bubbleMetadataByID[bodyID] else {
            return
        }
        if let linkID = metadata.linkID {
            if let onLinkedBubbleDeleted {
                onLinkedBubbleDeleted(linkID)
            } else {
                removeLinkedWordBubbles(ids: [linkID])
            }
            return
        }
        removeConversationBubbleGroup(startingAt: bodyID)
    }

    func removeBubbleView(bodyID: String) {
        for view in transcriptStack.arrangedSubviews {
            guard let box = view as? ChatBubbleView,
                  box.subviews.contains(where: { ($0 as? NSTextField)?.identifier?.rawValue == bodyID }) else {
                continue
            }
            transcriptStack.removeArrangedSubview(box)
            box.removeFromSuperview()
            break
        }
    }

    func removeConversationBubbleGroup(startingAt bodyID: String) {
        guard let startIndex = transcriptStack.arrangedSubviews.firstIndex(where: { view in
            guard let box = view as? ChatBubbleView else { return false }
            return bodyIDForBubbleBox(box) == bodyID
        }) else {
            return
        }

        var boxesToRemove: [ChatBubbleView] = []
        var idsToRemove: [String] = []
        var deletedBubbles: [SavedAIConversationBubble] = []
        for view in transcriptStack.arrangedSubviews[startIndex...] {
            guard let box = view as? ChatBubbleView,
                  let candidateID = bodyIDForBubbleBox(box),
                  let metadata = bubbleMetadataByID[candidateID],
                  metadata.linkID == nil else {
                continue
            }
            if !idsToRemove.isEmpty, metadata.role == AppText.userRole {
                break
            }
            boxesToRemove.append(box)
            idsToRemove.append(candidateID)
            deletedBubbles.append(SavedAIConversationBubble(
                role: metadata.role,
                text: metadata.text,
                collapsible: metadata.collapsible,
                renderMarkdown: metadata.renderMarkdown,
                sourceLocation: metadata.sourceLocation
            ))
        }

        guard !idsToRemove.isEmpty else { return }
        for box in boxesToRemove {
            transcriptStack.removeArrangedSubview(box)
            box.removeFromSuperview()
        }
        for removedID in idsToRemove {
            bubbleMetadataByID.removeValue(forKey: removedID)
            persistentBubbleIDs.removeAll { $0 == removedID }
        }
        onConversationBubblesDeleted?(deletedBubbles)
        notifyConversationChangedIfNeeded()
        transcriptStack.needsLayout = true
        scheduleTranscriptLayout()
    }

    func bodyIDForBubbleBox(_ box: ChatBubbleView) -> String? {
        box.subviews
            .compactMap { $0 as? NSTextField }
            .compactMap { $0.identifier?.rawValue }
            .first { bubbleMetadataByID[$0] != nil }
    }

    func savedConversation() -> SavedAIConversation {
        let normalBubbleIDs = persistentBubbleIDs.filter { bodyID in
            guard let metadata = bubbleMetadataByID[bodyID] else { return false }
            return metadata.linkID == nil
        }
        let savedBubbleIDs = Array(normalBubbleIDs.suffix(Self.maxSavedConversationBubbles))
        let bubbles = savedBubbleIDs.compactMap { bubbleMetadataByID[$0] }.map {
            SavedAIConversationBubble(
                role: $0.role,
                text: $0.text,
                collapsible: $0.collapsible,
                renderMarkdown: $0.renderMarkdown,
                sourceLocation: $0.sourceLocation
            )
        }
        return SavedAIConversation(bubbles: bubbles)
    }

    func defaultSourceLocation(role: String, text: String, linkID: String?) -> AIConversationSourceLocation? {
        guard shouldPersistBubble(role: role, text: text, linkID: linkID) else { return nil }
        return onCurrentSourceLocation?()
    }

    func shouldPersistBubble(role: String, text: String, linkID: String?) -> Bool {
        guard !isLoadingLinkedWordBubbles else { return false }
        if linkID != nil {
            return false
        }
        return role == AppText.userRole || role == AppText.aiRole || role == AppText.errorRole
    }

    func notifyConversationChangedIfNeeded() {
        guard !isRestoringSavedConversation else { return }
        onConversationChanged?(savedConversation())
        let sources = activeConversationSources()
        if sources != lastNotifiedConversationSources {
            lastNotifiedConversationSources = sources
            onConversationSourcesChanged?(sources)
        }
    }

    func activeConversationSources() -> [AIConversationSourceLocation] {
        var sources: [AIConversationSourceLocation] = []
        for bodyID in persistentBubbleIDs {
            guard let metadata = bubbleMetadataByID[bodyID],
                  metadata.linkID == nil,
                  let source = metadata.sourceLocation,
                  !sources.contains(source) else {
                continue
            }
            sources.append(source)
        }
        return sources
    }
}
