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

}
