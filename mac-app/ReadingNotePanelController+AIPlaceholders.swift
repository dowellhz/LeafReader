import Cocoa

extension ReadingNotePanelController {
    func appendAISection(title: String, body: String) {
        let suffix = markdownFromEditor().hasSuffix("\n") ? "" : "\n"
        renderMarkdownIntoEditor(markdownFromEditor() + "\(suffix)\n### \(title)\n\n\(body)\n")
        textView.scrollToEndOfDocument(nil)
        save()
    }

    func appendAIPlaceholder(title: String) {
        let placeholderText = AppText.localized(" 正在生成...", " Generating...")
        let suffix = markdownFromEditor().hasSuffix("\n") ? "" : "\n"
        let rendered = NSMutableAttributedString(attributedString: MarkdownRenderer.render(
            markdownFromEditor() + "\(suffix)\n### \(title)\n\n",
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        ))
        rendered.append(aiPlaceholderAttributedString(text: placeholderText))
        rendered.append(NSAttributedString(string: "\n"))
        textView.textStorage?.setAttributedString(rendered)
        editorState.aiPlaceholderDisplayText = "\(title)\n\n\u{fffc}\(placeholderText)"
        textView.scrollToEndOfDocument(nil)
    }

    func replaceAIPlaceholder(title: String, body: String) {
        let replacement = MarkdownRenderer.render(
            "### \(title)\n\n\(body)\n",
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        guard let range = aiPlaceholderRange() else {
            appendAISection(title: title, body: body)
            return
        }
        replaceText(in: range, with: replacement)
        textView.scrollToEndOfDocument(nil)
        editorState.aiPlaceholderDisplayText = nil
    }

    func removeAIPlaceholder() {
        guard let range = aiPlaceholderRange() else {
            editorState.aiPlaceholderDisplayText = nil
            return
        }
        replaceText(in: expandedPlaceholderRemovalRange(range), with: "")
        editorState.aiPlaceholderDisplayText = nil
    }

    private func aiPlaceholderRange() -> NSRange? {
        guard let display = editorState.aiPlaceholderDisplayText else { return nil }
        let range = (textView.string as NSString).range(of: display)
        return range.location == NSNotFound ? nil : range
    }

    private func expandedPlaceholderRemovalRange(_ range: NSRange) -> NSRange {
        let nsText = textView.string as NSString
        var location = range.location
        var length = range.length
        while location > 0, nsText.substring(with: NSRange(location: location - 1, length: 1)) == "\n" {
            location -= 1
            length += 1
        }
        while location + length < nsText.length,
              nsText.substring(with: NSRange(location: location + length, length: 1)) == "\n" {
            length += 1
        }
        return NSRange(location: location, length: length)
    }

    private func aiPlaceholderAttributedString(text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        attachment.image = symbol
        attachment.bounds = NSRect(x: 0, y: -2, width: 15, height: 15)
        output.append(NSAttributedString(attachment: attachment))
        output.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: ReadingNoteTheme.secondaryText(ReaderTheme.selected)
            ]
        ))
        return output
    }
}
