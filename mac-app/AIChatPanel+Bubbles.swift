import Cocoa

extension AIChatPanel {
    @discardableResult
    func appendBubble(
        role: String,
        text: String,
        collapsible: Bool = false,
        renderMarkdown: Bool = true,
        linkID: String? = nil,
        sourceLocation: AIConversationSourceLocation? = nil,
        persist: Bool? = nil
    ) -> NSTextField {
        let box = ChatBubbleView()
        box.fillColor = bubbleFillColor(role: role)
        box.borderColor = bubbleBorderColor
        box.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false

        let body = ChatBubbleTextField(wrappingLabelWithString: "")
        body.attributedStringValue = bubbleString(role: role, text: text, renderMarkdown: renderMarkdown)
        body.maximumNumberOfLines = collapsible ? 1 : 0
        body.isSelectable = true
        body.allowsEditingTextAttributes = true
        body.delegate = self
        body.translatesAutoresizingMaskIntoConstraints = false
        let bodyID = UUID().uuidString
        body.identifier = NSUserInterfaceItemIdentifier(bodyID)
        let effectiveSourceLocation = sourceLocation ?? defaultSourceLocation(role: role, text: text, linkID: linkID)
        bubbleMetadataByID[bodyID] = BubbleMetadata(
            role: role,
            text: text,
            renderMarkdown: renderMarkdown,
            collapsible: collapsible,
            linkID: linkID,
            sourceLocation: effectiveSourceLocation
        )

        box.addSubview(body)
        let speakerButton: NSButton?
        if let word = speakerWordForBubble(role: role, text: text, linkID: linkID) {
            let button = WordSpeakerButton(title: "", target: self, action: #selector(playBubbleWord(_:)))
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = NSColor.systemBlue
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.identifier = NSUserInterfaceItemIdentifier(word)
            button.spokenWord = word
            button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
            button.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(button)
            speakerButton = button
            body.setContentHuggingPriority(.required, for: .horizontal)
            body.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            speakerButton = nil
        }
        transcriptStack.addArrangedSubview(box)
        if let linkID {
            box.identifier = NSUserInterfaceItemIdentifier(linkID)
            if bubbleBoxByLinkID[linkID] == nil || speakerButton != nil {
                bubbleBoxByLinkID[linkID] = box
            }
            if speakerButton == nil {
                box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(selectLinkedBubble(_:))))
            }
        } else if effectiveSourceLocation != nil {
            box.identifier = NSUserInterfaceItemIdentifier(bodyID)
            box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(selectConversationSourceBubble(_:))))
        } else if collapsible {
            box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleCollapsedBubble(_:))))
            box.toolTip = AppText.tapToExpand
        }

        var constraints: [NSLayoutConstraint] = [
            box.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            body.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ]
        if let speakerButton {
            constraints.append(contentsOf: [
                body.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -78),
                speakerButton.leadingAnchor.constraint(equalTo: body.trailingAnchor, constant: 2),
                speakerButton.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
                speakerButton.centerYAnchor.constraint(equalTo: body.centerYAnchor),
                speakerButton.widthAnchor.constraint(equalToConstant: 54),
                speakerButton.heightAnchor.constraint(equalToConstant: 54)
            ])
        } else {
            constraints.append(body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12))
        }
        NSLayoutConstraint.activate(constraints)

        if persist ?? shouldPersistBubble(role: role, text: text, linkID: linkID) {
            persistentBubbleIDs.append(bodyID)
            trimVisibleNormalConversationBubblesIfNeeded()
        }
        notifyConversationChangedIfNeeded()

        scheduleTranscriptLayout(scrollTarget: box, forceScroll: true)
        return body
    }

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

    func speakerWordForBubble(role: String, text: String, linkID: String?) -> String? {
        guard linkID != nil, role == AppText.userRole else { return nil }
        let rawWord = vocabularyWord(from: text)
        return isSingleEnglishWord(rawWord) ? rawWord : nil
    }

    @objc func playBubbleWord(_ sender: NSButton) {
        let candidate = (sender as? WordSpeakerButton)?.spokenWord ?? sender.identifier?.rawValue
        guard let word = candidate,
              isSingleEnglishWord(word) else {
            return
        }
        speakWord(word)
    }

    func updateBubble(_ body: NSTextField, role: String, text: String, renderMarkdown: Bool = true, notify: Bool = true) {
        let existingMetadata = body.identifier.flatMap { bubbleMetadataByID[$0.rawValue] }
        if let bodyID = body.identifier?.rawValue {
            bubbleMetadataByID[bodyID] = BubbleMetadata(
                role: role,
                text: text,
                renderMarkdown: renderMarkdown,
                collapsible: existingMetadata?.collapsible ?? false,
                linkID: existingMetadata?.linkID,
                sourceLocation: existingMetadata?.sourceLocation
            )
        }
        body.attributedStringValue = bubbleString(role: role, text: text, renderMarkdown: renderMarkdown)
        body.invalidateIntrinsicContentSize()
        body.superview?.invalidateIntrinsicContentSize()
        scheduleTranscriptLayout(scrollTarget: body.superview ?? body)
        if notify {
            notifyConversationChangedIfNeeded()
        }
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

    func restoreBubbleRendering(_ body: NSTextField) {
        guard let bodyID = body.identifier?.rawValue,
              let metadata = bubbleMetadataByID[bodyID] else {
            return
        }
        let rendered = NSMutableAttributedString(attributedString: bubbleString(
            role: metadata.role,
            text: metadata.text,
            renderMarkdown: metadata.renderMarkdown
        ))
        if body === activeBubbleTextField,
           let highlightRange = activeBubbleHighlightRange(in: rendered) {
            rendered.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55), range: highlightRange)
        }
        body.attributedStringValue = rendered
        body.needsDisplay = true
    }

    func activeBubbleHighlightRange(in rendered: NSAttributedString) -> NSRange? {
        if let range = activeBubbleSelectionRange,
           range.location != NSNotFound,
           range.location + range.length <= rendered.length {
            return range
        }
        let selected = activeBubbleSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return nil }
        let fallbackRange = (rendered.string as NSString).range(of: selected)
        return fallbackRange.location == NSNotFound ? nil : fallbackRange
    }

    func scheduleStreamUpdate(_ body: NSTextField, text: String) {
        pendingStreamText = text
        let minimumInterval: TimeInterval = 0.10
        let elapsed = Date().timeIntervalSince(lastStreamUpdateAt)
        if streamUpdateWorkItem == nil, elapsed >= minimumInterval {
            applyPendingStreamUpdate(body)
            return
        }
        guard streamUpdateWorkItem == nil else { return }
        let delay = max(0, minimumInterval - elapsed)
        let workItem = DispatchWorkItem { [weak self, weak body] in
            guard let self, let body else { return }
            guard self.streamUpdateWorkItem?.isCancelled == false else {
                self.streamUpdateWorkItem = nil
                return
            }
            self.streamUpdateWorkItem = nil
            self.applyPendingStreamUpdate(body)
        }
        streamUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func flushStreamUpdate(_ body: NSTextField?) {
        streamUpdateWorkItem?.cancel()
        streamUpdateWorkItem = nil
        guard let body, !pendingStreamText.isEmpty else { return }
        applyPendingStreamUpdate(body)
    }

    private func applyPendingStreamUpdate(_ body: NSTextField) {
        guard !pendingStreamText.isEmpty else { return }
        lastStreamUpdateAt = Date()
        updateBubble(body, role: AppText.aiRole, text: pendingStreamText, renderMarkdown: false, notify: false)
    }

    func bubbleString(role: String, text: String, renderMarkdown: Bool) -> NSAttributedString {
        if role == AppText.userRole, isVocabularyBubbleTitle(text) {
            return vocabularyTitleString(text)
        }
        return role == AppText.aiRole && renderMarkdown ? markdownString(text) : plainString(text)
    }

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

    func plainString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.readerBodyFontSize),
            .foregroundColor: primaryTextColor,
            .paragraphStyle: paragraphStyle(spacing: 8)
        ])
    }

    func vocabularyBubbleTitle(for word: String) -> String {
        "\(AppText.localized("单词", "Word"))：\(word.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func isVocabularyBubbleTitle(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("单词：")
            || normalized.hasPrefix("单词:")
            || normalized.lowercased().hasPrefix("word:")
            || isSingleEnglishWord(normalized)
    }

    func vocabularyWord(from text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["：", ":"] {
            if let range = normalized.range(of: separator) {
                return String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return normalized
    }

    func vocabularyTitleString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: AppFont.semibold(ofSize: Self.readerBodyFontSize),
            .foregroundColor: primaryTextColor,
            .paragraphStyle: paragraphStyle(spacing: 8)
        ])
    }

    func markdownString(_ text: String) -> NSAttributedString {
        MarkdownRenderer.render(text, fontSize: Self.readerBodyFontSize, textColor: primaryTextColor)
    }

    func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
        return style
    }

    var panelBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
            : NSColor.white.withAlphaComponent(0.97)
    }

    var primaryTextColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1)
            : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
    }

    var secondaryTextColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1)
            : NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
    }

    var inputBackgroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
    }

    var bubbleBorderColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)
            : NSColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1)
    }

    func bubbleFillColor(role: String) -> NSColor {
        guard isDarkMode else {
            return role == AppText.userRole ? NSColor(red: 0.92, green: 0.96, blue: 1, alpha: 1) : .white
        }
        return role == AppText.userRole
            ? NSColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1)
            : NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
    }

    func restyleTranscript() {
        let entries = transcriptStack.arrangedSubviews.compactMap { view -> BubbleMetadata? in
            guard
                let box = view as? NSBox,
                let body = box.subviews.compactMap({ $0 as? NSTextField }).first,
                let bodyID = body.identifier?.rawValue,
                let metadata = bubbleMetadataByID[bodyID]
            else {
                return nil
            }
            return metadata
        }

        if !entries.isEmpty {
            transcriptStack.arrangedSubviews.forEach { view in
                transcriptStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            bubbleMetadataByID.removeAll()
            for metadata in entries {
                appendBubble(
                    role: metadata.role,
                    text: metadata.text,
                    collapsible: metadata.collapsible,
                    renderMarkdown: metadata.renderMarkdown,
                    linkID: metadata.linkID,
                    sourceLocation: metadata.sourceLocation
                )
            }
            updateLinkedBubbleSelection()
            return
        }

        for box in transcriptStack.arrangedSubviews.compactMap({ $0 as? ChatBubbleView }) {
            box.borderColor = bubbleBorderColor
            guard let body = box.subviews.compactMap({ $0 as? NSTextField }).first else { continue }
            let metadata: BubbleMetadata?
            if let bodyID = body.identifier?.rawValue {
                metadata = bubbleMetadataByID[bodyID]
            } else {
                metadata = nil
            }
            let role = metadata?.role ?? AppText.aiRole
            let fillColor = bubbleFillColor(role: role)
            box.fillColor = fillColor
            if let metadata {
                body.attributedStringValue = bubbleString(role: metadata.role, text: metadata.text, renderMarkdown: metadata.renderMarkdown)
            } else {
                box.fillColor = bubbleFillColor(role: AppText.aiRole)
                let updated = NSMutableAttributedString(attributedString: body.attributedStringValue)
                updated.addAttribute(.foregroundColor, value: primaryTextColor, range: NSRange(location: 0, length: updated.length))
                body.attributedStringValue = updated
            }
            box.needsDisplay = true
            body.needsDisplay = true
        }
        updateLinkedBubbleSelection()
        transcriptStack.needsLayout = true
        scheduleTranscriptLayout()
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
