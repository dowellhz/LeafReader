import Cocoa

extension AIChatPanel {
    @objc func toggleCollapsedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard
            let box = recognizer.view as? ChatBubbleView,
            let body = box.subviews.compactMap({ $0 as? NSTextField }).first
        else { return }

        body.maximumNumberOfLines = body.maximumNumberOfLines == 1 ? 0 : 1
        body.invalidateIntrinsicContentSize()
        box.invalidateIntrinsicContentSize()
        scheduleTranscriptLayout(scrollTarget: box, forceScroll: true)
    }

    @objc func selectLinkedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard let box = recognizer.view as? ChatBubbleView,
              !isClickOnBubbleButton(recognizer, in: box),
              let linkID = box.identifier?.rawValue else { return }
        selectedLinkID = linkID
        updateLinkedBubbleSelection()
        onLinkedBubbleSelected?(linkID)
    }

    @objc func selectConversationSourceBubble(_ recognizer: NSClickGestureRecognizer) {
        guard let box = recognizer.view as? ChatBubbleView,
              !isClickOnBubbleButton(recognizer, in: box),
              let bodyID = box.identifier?.rawValue,
              let sourceLocation = bubbleMetadataByID[bodyID]?.sourceLocation else {
            return
        }
        onConversationBubbleSelected?(sourceLocation)
    }

    func isClickOnBubbleButton(_ recognizer: NSClickGestureRecognizer, in box: ChatBubbleView) -> Bool {
        let location = recognizer.location(in: box)
        return box.subviews.contains { subview in
            subview is NSButton && subview.frame.contains(location)
        }
    }

    func updateLinkedBubbleSelection() {
        for (linkID, box) in bubbleBoxByLinkID {
            box.borderColor = linkID == selectedLinkID
                ? NSColor.systemBlue.withAlphaComponent(0.9)
                : bubbleBorderColor
            box.needsDisplay = true
        }
    }

    func scrollTranscriptToTop(of box: NSView) {
        flushTranscriptLayout()
        guard let documentView = scrollView.documentView else {
            box.scrollToVisible(box.bounds)
            return
        }
        let boxFrame = box.convert(box.bounds, to: documentView)
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.y = min(
            max(0, boxFrame.minY - 8),
            max(0, documentView.bounds.height - clipView.bounds.height)
        )
        origin.x = 0
        clipView.animator().setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func scrollToConversationSource(_ source: AIConversationSourceLocation) {
        let preferredRoles = [AppText.aiRole, AppText.userRole]
        for role in preferredRoles {
            if let bodyID = bubbleMetadataByID.first(where: { _, metadata in
                metadata.role == role && metadata.sourceLocation == source
            })?.key,
               let box = bubbleBox(containingBodyID: bodyID) {
                setContentVisible(true)
                DispatchQueue.main.async { [weak self, weak box] in
                    guard let self, let box else { return }
                    self.scrollTranscriptToTop(of: box)
                }
                return
            }
        }
    }

    private func bubbleBox(containingBodyID bodyID: String) -> ChatBubbleView? {
        transcriptStack.arrangedSubviews.compactMap { $0 as? ChatBubbleView }.first { box in
            box.subviews.contains { subview in
                (subview as? NSTextField)?.identifier?.rawValue == bodyID
            }
        }
    }

    func scheduleTranscriptLayout(scrollTarget: NSView? = nil, forceScroll: Bool = false) {
        if let scrollTarget, forceScroll || isTranscriptScrolledNearBottom() {
            pendingTranscriptScrollTarget = scrollTarget
        }
        pendingTranscriptForceScroll = pendingTranscriptForceScroll || forceScroll

        guard transcriptLayoutWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.transcriptLayoutWorkItem?.isCancelled == false else {
                self.transcriptLayoutWorkItem = nil
                return
            }
            self.transcriptLayoutWorkItem = nil
            self.applyPendingTranscriptLayout()
        }
        transcriptLayoutWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func flushTranscriptLayout() {
        transcriptLayoutWorkItem?.cancel()
        transcriptLayoutWorkItem = nil
        applyPendingTranscriptLayout()
    }

    private func applyPendingTranscriptLayout() {
        transcriptStack.layoutSubtreeIfNeeded()
        if let target = pendingTranscriptScrollTarget,
           pendingTranscriptForceScroll || isTranscriptScrolledNearBottom(tolerance: 140) {
            target.scrollToVisible(target.bounds)
        }
        pendingTranscriptScrollTarget = nil
        pendingTranscriptForceScroll = false
    }

    func isTranscriptScrolledNearBottom(tolerance: CGFloat = 80) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentMaxY = documentView.bounds.maxY
        return contentMaxY <= scrollView.contentView.bounds.height || visibleMaxY >= contentMaxY - tolerance
    }
}
