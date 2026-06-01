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
        regenerationRequest: RegenerationRequest? = nil,
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
            sourceLocation: effectiveSourceLocation,
            regenerationRequest: regenerationRequest
        )

        box.addSubview(body)
        let deleteButton = makeBubbleDeleteButton(bodyID: bodyID, role: role)
        if let deleteButton {
            box.addSubview(deleteButton)
        }
        let copyButton = makeBubbleCopyMarkdownButton(bodyID: bodyID, role: role)
        if let copyButton {
            box.addSubview(copyButton)
        }
        let regenerateButton = makeBubbleRegenerateButton(bodyID: bodyID, role: role, linkID: linkID, request: regenerationRequest)
        if let regenerateButton {
            box.addSubview(regenerateButton)
        }
        let sourceLabel: NSTextField?
        if role == AppText.aiRole, let effectiveSourceLocation {
            let label = NSTextField(labelWithString: sourceSummaryText(for: effectiveSourceLocation))
            label.font = AppFont.semibold(ofSize: 11)
            label.textColor = sourceSummaryTextColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.wantsLayer = true
            label.layer?.backgroundColor = sourceSummaryBackgroundColor.cgColor
            label.layer?.cornerRadius = 5
            label.layer?.masksToBounds = true
            label.toolTip = sourceTooltipText(for: effectiveSourceLocation)
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            sourceLabel = label
        } else {
            sourceLabel = nil
        }
        let speakerButton: NSButton?
        if let word = speakerWordForBubble(role: role, text: text, linkID: linkID) {
            let button = WordSpeakerButton(title: "", target: self, action: #selector(playBubbleWord(_:)))
            button.image = TemplateSymbolImage.make("speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = aiAccentColor
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
                addBubbleBodyClick(to: body, action: #selector(selectLinkedBubble(_:)))
            }
        } else if effectiveSourceLocation != nil {
            box.identifier = NSUserInterfaceItemIdentifier(bodyID)
            addBubbleBodyClick(to: body, action: #selector(selectConversationSourceBubble(_:)))
        } else if collapsible {
            addBubbleBodyClick(to: body, action: #selector(toggleCollapsedBubble(_:)))
            box.toolTip = AppText.tapToExpand
        }

        var constraints: [NSLayoutConstraint] = [
            box.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ]
        let headerButtons = [deleteButton, copyButton, regenerateButton].compactMap { $0 }
        let headerLeadingButton = installBubbleHeaderButtons(headerButtons, in: box, constraints: &constraints)
        if let sourceLabel {
            let sourceTrailingAnchor = headerLeadingButton?.leadingAnchor ?? box.trailingAnchor
            let sourceTrailingConstant: CGFloat = headerLeadingButton == nil ? -12 : -8
            constraints.append(contentsOf: [
                sourceLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
                sourceLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: sourceTrailingAnchor, constant: sourceTrailingConstant),
                body.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 8)
            ])
        } else {
            constraints.append(body.topAnchor.constraint(equalTo: box.topAnchor, constant: 12))
        }
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

    private func installBubbleHeaderButtons(
        _ buttons: [NSButton],
        in box: ChatBubbleView,
        constraints: inout [NSLayoutConstraint]
    ) -> NSButton? {
        var previousLeadingAnchor: NSLayoutXAxisAnchor?
        for button in buttons {
            constraints.append(contentsOf: [
                button.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
                button.trailingAnchor.constraint(equalTo: previousLeadingAnchor ?? box.trailingAnchor, constant: previousLeadingAnchor == nil ? -8 : -4),
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 30)
            ])
            previousLeadingAnchor = button.leadingAnchor
        }
        return buttons.last
    }

    func makeBubbleDeleteButton(bodyID: String, role: String) -> NSButton? {
        guard role == AppText.userRole else { return nil }
        let button = BubbleDeleteButton(title: "", target: self, action: #selector(deleteBubble(_:)))
        button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: AppText.localized("删除气泡", "Delete bubble"))
        button.isBordered = false
        button.contentTintColor = secondaryTextColor
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier(bodyID)
        button.toolTip = AppText.localized("删除这段气泡", "Delete this bubble")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func makeBubbleRegenerateButton(bodyID: String, role: String, linkID: String?, request: RegenerationRequest?) -> NSButton? {
        guard role == AppText.aiRole,
              linkID == nil,
              request != nil else {
            return nil
        }
        let button = BubbleDeleteButton(title: "", target: self, action: #selector(regenerateBubble(_:)))
        button.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: AppText.localized("重新生成", "Regenerate")
        )
        button.isBordered = false
        button.contentTintColor = secondaryTextColor
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier(bodyID)
        button.toolTip = AppText.localized("重新生成这段回答", "Regenerate this answer")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func makeBubbleCopyMarkdownButton(bodyID: String, role: String) -> NSButton? {
        guard role == AppText.aiRole else { return nil }
        let button = BubbleDeleteButton(title: "", target: self, action: #selector(copyBubbleMarkdown(_:)))
        button.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: AppText.localized("复制 Markdown", "Copy Markdown")
        )
        button.isBordered = false
        button.contentTintColor = secondaryTextColor
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier(bodyID)
        button.toolTip = AppText.localized("复制这段回答的 Markdown", "Copy this answer as Markdown")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func addBubbleBodyClick(to body: NSTextField, action: Selector) {
        body.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: action))
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
                sourceLocation: existingMetadata?.sourceLocation,
                regenerationRequest: existingMetadata?.regenerationRequest
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
            rendered.addAttribute(.backgroundColor, value: aiSelectionBackgroundColor, range: highlightRange)
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

}
