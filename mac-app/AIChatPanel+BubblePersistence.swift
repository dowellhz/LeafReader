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

        let activeBodyID = activeAssistantBody?.identifier?.rawValue
        for bodyID in normalBubbleIDs.prefix(excessCount) where bodyID != activeBodyID {
            removeConversationBubble(bodyID: bodyID)
        }
    }

    func removeConversationBubble(bodyID: String) {
        guard let metadata = bubbleMetadataByID[bodyID],
              metadata.linkID == nil else { return }
        for view in transcriptStack.arrangedSubviews {
            guard let box = view as? ChatBubbleView,
                  box.subviews.contains(where: { ($0 as? NSTextField)?.identifier?.rawValue == bodyID }) else {
                continue
            }
            transcriptStack.removeArrangedSubview(box)
            box.removeFromSuperview()
            break
        }
        bubbleMetadataByID.removeValue(forKey: bodyID)
        persistentBubbleIDs.removeAll { $0 == bodyID }
        notifyConversationChangedIfNeeded()
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
