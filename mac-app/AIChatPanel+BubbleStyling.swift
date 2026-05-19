import Cocoa

extension AIChatPanel {
    func bubbleString(role: String, text: String, renderMarkdown: Bool) -> NSAttributedString {
        if role == AppText.userRole, isVocabularyBubbleTitle(text) {
            return vocabularyTitleString(text)
        }
        return role == AppText.aiRole && renderMarkdown ? markdownString(text) : plainString(text)
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
            box.fillColor = bubbleFillColor(role: role)
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
}
