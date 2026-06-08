import Cocoa

extension ReadingNotePanelController {
    func showSlashCommandMenu() {
        guard let trigger = slashCommandTrigger() else { return }
        aiToolbarContainer.isHidden = true
        askInputContainer.isHidden = true

        let menu = NSMenu()
        for group in ReadingNoteSlashCommand.menuCommandGroups(isLineCommand: trigger.isLineCommand) {
            menu.addItem(disabledSlashMenuHeader(slashCommandGroupTitle(group)))
            group.forEach { menu.addItem(slashMenuItem($0)) }
            menu.addItem(.separator())
        }

        menu.addItem(closeSlashMenuItem())
        menu.popUp(positioning: nil, at: slashCommandMenuPoint(), in: textView)
    }

    @objc func slashCommandSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = ReadingNoteSlashCommand(rawValue: raw) else { return }
        runSlashCommand(command)
    }

    func runSlashContinuation() {
        let prefix = textBeforeCurrentSlashTrigger().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return }
        runAIAction(
            .continueLine,
            title: AppText.localized("补充", "Continue"),
            sourceText: prefix,
            replaceSlashTrigger: true
        )
    }

    private func runSlashCommand(_ command: ReadingNoteSlashCommand) {
        switch command {
        case .text:
            replaceCurrentSlashLineWithMarkdownBlock(.paragraph)
        case .heading1:
            replaceCurrentSlashLineWithMarkdownBlock(.heading1)
        case .heading2:
            replaceCurrentSlashLineWithMarkdownBlock(.heading2)
        case .heading3:
            replaceCurrentSlashLineWithMarkdownBlock(.heading3)
        case .heading4:
            replaceCurrentSlashLineWithMarkdownBlock(.heading4)
        case .bulletedList, .numberedList:
            replaceCurrentSlashLineWithEditablePrefix(command.marker)
        case .template:
            replaceCurrentSlashLine(with: "")
            applyTemplate(.reading)
        case .aiContinue:
            runSlashContinuation()
        case .aiExplain:
            replaceCurrentSlashLine(with: "")
            runAIAction(.explain, title: AppText.localized("解析", "Explain"))
        case .aiTranslate:
            replaceCurrentSlashLine(with: "")
            runAIAction(.translate, title: AppText.localized("翻译", "Translate"))
        case .aiSummarize:
            replaceCurrentSlashLine(with: "")
            runAIAction(.summarize, title: AppText.localized("总结", "Summarize"))
        case .aiOrganize:
            replaceCurrentSlashLine(with: "")
            runAIAction(
                .polish,
                title: AppText.localized("整理", "Organize"),
                replaceSelection: true,
                renderMarkdownReplacement: true
            )
        }
    }

    private func slashMenuItem(_ command: ReadingNoteSlashCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(slashCommandSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command.rawValue
        if !command.marker.isEmpty {
            item.attributedTitle = slashMenuAttributedTitle(title: command.title, marker: command.marker)
        }
        return item
    }

    private func slashCommandGroupTitle(_ commands: [ReadingNoteSlashCommand]) -> String {
        commands.allSatisfy(\.isAICommand) ? "AI" : AppText.localized("基础块", "Basic blocks")
    }

    private func disabledSlashMenuHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func closeSlashMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: AppText.localized("关闭菜单", "Close menu"), action: nil, keyEquivalent: "\u{1b}")
        item.isEnabled = false
        return item
    }

    private func slashMenuAttributedTitle(title: String, marker: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributed.append(NSAttributedString(
            string: "    \(marker)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        ))
        return attributed
    }

    private func slashCommandMenuPoint() -> NSPoint {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSPoint(x: textView.textContainerInset.width, y: textView.bounds.maxY - textView.textContainerInset.height)
        }
        let location = min(textView.selectedRange().location, (textView.string as NSString).length)
        let glyphIndex = location > 0 ? layoutManager.glyphIndexForCharacter(at: location - 1) : 0
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return NSPoint(x: rect.minX, y: rect.minY - 6)
    }

    private struct SlashCommandTrigger {
        let isLineCommand: Bool
    }

    private func slashCommandTrigger() -> SlashCommandTrigger? {
        guard let trigger = ReadingNoteSlashRangePolicy.trigger(
            text: textView.string,
            selection: textView.selectedRange()
        ) else { return nil }
        return SlashCommandTrigger(isLineCommand: trigger.isLineCommand)
    }

    private func textBeforeCurrentSlashTrigger() -> String {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        guard location > 0 else { return "" }
        return nsText.substring(to: location - 1)
    }
}
