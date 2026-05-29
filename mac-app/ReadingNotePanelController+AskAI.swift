import Cocoa

extension ReadingNotePanelController {
    func installAskInputKeyMonitor() {
        askInputKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleAskInputKeyDown(event) ?? event
        }
    }

    func setAskInputVisible(_ visible: Bool) {
        askInputContainer.isHidden = !visible
        textView.isEditable = !visible
        if !visible, window?.firstResponder === askInputField.currentEditor() {
            window?.makeFirstResponder(textView)
        }
    }

    func refreshAIToolbar() {
        let enabled = !aiRunner.isRunning
        aiActionButtons.forEach { $0.isEnabled = enabled }
        if isAskInputVisible {
            positionAskInputNearSelection()
            return
        }
        guard !aiRunner.isRunning, selectedText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            aiToolbarContainer.isHidden = true
            return
        }
        updateAIToolbarPosition()
        aiToolbarContainer.isHidden = false
    }

    @objc func explainSelection(_ sender: NSButton) {
        runAIAction(.explain, title: AppText.localized("解析", "Explain"))
    }

    @objc func translateSelection(_ sender: NSButton) {
        runAIAction(.translate, title: AppText.localized("翻译", "Translate"))
    }

    @objc func summarizeSelection(_ sender: NSButton) {
        runAIAction(.summarize, title: AppText.localized("总结", "Summarize"))
    }

    @objc func polishSelection(_ sender: NSButton) {
        runAIAction(
            .polish,
            title: AppText.localized("整理", "Organize"),
            replaceSelection: true,
            renderMarkdownReplacement: true
        )
    }

    @objc func showAskInput(_ sender: NSButton) {
        let selected = selectedText()
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        pendingAskSelectedText = selected
        askInputField.stringValue = ""
        aiToolbarContainer.isHidden = true
        positionAskInputNearSelection()
        setAskInputVisible(true)
        window?.makeFirstResponder(askInputField)
    }

    @objc func submitAskQuestion(_ sender: Any?) {
        let question = askInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = makeAskRequest(question: question) else { return }
        runAskQuestion(request)
    }

    func showSlashCommandMenu() {
        guard let trigger = slashCommandTrigger() else { return }
        aiToolbarContainer.isHidden = true
        askInputContainer.isHidden = true

        let menu = NSMenu()
        if trigger.isLineCommand {
            menu.addItem(disabledMenuHeader(AppText.localized("基础块", "Basic blocks")))
            for command in ReadingNoteSlashCommand.blockCommands {
                menu.addItem(slashMenuItem(command))
            }
            menu.addItem(.separator())
        }
        menu.addItem(disabledMenuHeader("AI"))
        for command in trigger.isLineCommand ? ReadingNoteSlashCommand.aiCommands : [.aiContinue] {
            menu.addItem(slashMenuItem(command))
        }
        menu.addItem(.separator())
        let close = NSMenuItem(title: AppText.localized("关闭菜单", "Close menu"), action: nil, keyEquivalent: "\u{1b}")
        close.isEnabled = false
        menu.addItem(close)
        let point = slashCommandMenuPoint()
        menu.popUp(positioning: nil, at: point, in: textView)
    }

    @objc func slashCommandSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = ReadingNoteSlashCommand(rawValue: raw) else { return }
        runSlashCommand(command)
    }

    func runSlashContinuation() {
        let prefix = textBeforeCurrentSlashTrigger().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return }
        runAIAction(.continueLine, title: AppText.localized("补充", "Continue"), sourceText: prefix, replaceSlashTrigger: true)
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

    private func disabledMenuHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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

    private func handleAskInputKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === window,
              isAskInputVisible,
              event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              event.modifierFlags.intersection([.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }
        guard Self.askInputForwardedShortcutKeys.contains(key) else { return event }

        window?.makeFirstResponder(askInputField)
        guard let editor = askInputField.currentEditor() else { return nil }
        switch key {
        case "a":
            editor.selectAll(nil)
        case "c":
            editor.copy(nil)
        case "x":
            editor.cut(nil)
        case "v":
            editor.paste(nil)
        default:
            break
        }
        return nil
    }

    private struct SlashCommandTrigger {
        let slashRange: NSRange
        let lineRange: NSRange
        let isLineCommand: Bool
    }

    private func slashCommandTrigger() -> SlashCommandTrigger? {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        guard location > 0,
              nsText.substring(with: NSRange(location: location - 1, length: 1)) == "/" else {
            return nil
        }
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return SlashCommandTrigger(
            slashRange: NSRange(location: location - 1, length: 1),
            lineRange: lineRange,
            isLineCommand: line == "/"
        )
    }

    private func runAIAction(
        _ action: AITextActionRunner.Action,
        title: String,
        sourceText: String? = nil,
        replaceSlashTrigger: Bool = false,
        replaceSelection: Bool = false,
        renderMarkdownReplacement: Bool = false
    ) {
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            statusLabel.stringValue = AppText.localized("请先配置 API Key", "Configure API Key first")
            NSSound.beep()
            return
        }
        let selectionRange = textView.selectedRange()
        let text = sourceText ?? selectedText(in: selectionRange)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLabel.stringValue = AppText.localized("请先选中笔记中的文字", "Select text in the note first")
            NSSound.beep()
            return
        }
        setRunning(true, title: title)
        aiToolbarContainer.isHidden = true
        let usesTailPlaceholder = !replaceSlashTrigger && !replaceSelection
        if usesTailPlaceholder {
            appendAIPlaceholder(title: title)
        }
        aiRunner.run(action: action, text: text, noteContext: textView.string) { [weak self] result in
            guard let self else { return }
            self.setRunning(false, title: "")
            switch result {
            case .success(let output):
                let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                if replaceSlashTrigger {
                    self.replaceCurrentSlashTrigger(with: value)
                } else if replaceSelection {
                    if renderMarkdownReplacement {
                        self.replaceSelectionWithMarkdown(value, selectionRange: selectionRange)
                    } else {
                        self.replaceSelectedText(in: selectionRange, with: value)
                    }
                } else if usesTailPlaceholder {
                    self.replaceAIPlaceholder(title: title, body: value)
                } else {
                    self.appendAISection(title: title, body: value)
                }
            case .failure(let error):
                if usesTailPlaceholder {
                    self.removeAIPlaceholder()
                }
                self.statusLabel.stringValue = self.userFacingError(error)
            }
        }
    }

    private func replaceSelectionWithMarkdown(_ value: String, selectionRange: NSRange) {
        let markdown = markdownBody(from: value)
        let rendered = MarkdownRenderer.render(
            markdown,
            fontSize: 15,
            textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected)
        )
        replaceSelectedText(in: selectionRange, with: rendered)
    }

    private func markdownBody(from value: String) -> String {
        var lines = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix("```") else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        lines.removeFirst()
        if let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), last == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeAskRequest(question: String) -> AskRequest? {
        guard !question.isEmpty else {
            NSSound.beep()
            return nil
        }
        let selected = pendingAskSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            statusLabel.stringValue = AppText.localized("请先选中笔记中的文字", "Select text in the note first")
            NSSound.beep()
            return nil
        }
        return AskRequest(question: question, selectedText: selected)
    }

    private func runAskQuestion(_ request: AskRequest) {
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            statusLabel.stringValue = AppText.localized("请先配置 API Key", "Configure API Key first")
            NSSound.beep()
            return
        }
        setAskInputVisible(false)
        askInputField.stringValue = ""
        window?.makeFirstResponder(textView)
        setRunning(true, title: AppText.localized("问 AI", "Ask AI"))
        appendAIPlaceholder(title: request.question)
        if let onDocumentQuestionPrompt {
            onDocumentQuestionPrompt(documentQuestionPromptRequest(for: request)) { [weak self] prompt in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.runAskPrompt(prompt, request: request)
                    } else {
                        self.runAskFallback(request)
                    }
                }
            }
            return
        }
        runAskFallback(request)
    }

    private func documentQuestionPromptRequest(for request: AskRequest) -> DocumentQuestionPromptRequest {
        DocumentQuestionPromptRequest(
            question: request.question,
            questionSubject: request.selectedText,
            context: askDocumentContext(selectedText: request.selectedText)
        )
    }

    private func runAskPrompt(_ prompt: String, request: AskRequest) {
        aiRunner.runPrompt(prompt, systemPrompt: AIPromptStore.compactSystemPrompt()) { [weak self] result in
            self?.finishAskQuestion(result, request: request)
        }
    }

    private func runAskFallback(_ request: AskRequest) {
        aiRunner.runQuestion(
            question: request.question,
            selectedText: request.selectedText,
            systemPrompt: AIPromptStore.compactSystemPrompt()
        ) { [weak self] result in
            self?.finishAskQuestion(result, request: request)
        }
    }

    private func finishAskQuestion(_ result: Result<String, Error>, request: AskRequest) {
        setRunning(false, title: "")
        switch result {
        case .success(let output):
            let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            replaceAIPlaceholder(title: request.question, body: value)
            pendingAskSelectedText = ""
        case .failure(let error):
            removeAIPlaceholder()
            statusLabel.stringValue = userFacingError(error)
        }
    }

    private func askDocumentContext(selectedText: String) -> String {
        if AppText.isChinese {
            return """
            【阅读笔记选中内容】
            \(selectedText)

            【当前阅读笔记】
            \(ReaderAIContextPolicy.prefix(markdownFromEditor(), limit: 2000))
            """
        }
        return """
        [Selected reading-note text]
        \(selectedText)

        [Current reading note]
        \(ReaderAIContextPolicy.prefix(markdownFromEditor(), limit: 2000))
        """
    }

    private func setRunning(_ running: Bool, title: String) {
        statusLabel.stringValue = running ? AppText.localized("\(title)中...", "\(title)...") : ""
        refreshAIToolbar()
    }

    private func appendAISection(title: String, body: String) {
        let suffix = markdownFromEditor().hasSuffix("\n") ? "" : "\n"
        renderMarkdownIntoEditor(markdownFromEditor() + "\(suffix)\n### \(title)\n\n\(body)\n")
        textView.scrollToEndOfDocument(nil)
        save()
    }

    private func appendAIPlaceholder(title: String) {
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
        aiPlaceholderDisplayText = "\(title)\n\n\u{fffc}\(placeholderText)"
        textView.scrollToEndOfDocument(nil)
    }

    private func replaceAIPlaceholder(title: String, body: String) {
        let replacement = MarkdownRenderer.render("### \(title)\n\n\(body)\n", fontSize: 15, textColor: ReadingNoteTheme.primaryText(ReaderTheme.selected))
        guard let range = aiPlaceholderRange() else {
            appendAISection(title: title, body: body)
            return
        }
        replaceText(in: range, with: replacement)
        textView.scrollToEndOfDocument(nil)
        aiPlaceholderDisplayText = nil
    }

    private func removeAIPlaceholder() {
        guard let range = aiPlaceholderRange() else {
            aiPlaceholderDisplayText = nil
            return
        }
        replaceText(in: expandedPlaceholderRemovalRange(range), with: "")
        aiPlaceholderDisplayText = nil
    }

    private func aiPlaceholderRange() -> NSRange? {
        guard let display = aiPlaceholderDisplayText else { return nil }
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

    private func textBeforeCurrentSlashTrigger() -> String {
        let nsText = textView.string as NSString
        let location = min(textView.selectedRange().location, nsText.length)
        guard location > 0 else { return "" }
        return nsText.substring(to: location - 1)
    }

    private func userFacingError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == -10 {
            return AppText.localized("请先配置 API Key", "Configure API Key first")
        }
        if nsError.domain == NSURLErrorDomain {
            return AppText.localized("AI 请求失败，请检查网络", "AI request failed. Check the network.")
        }
        return AppText.localized("AI 请求失败", "AI request failed")
    }
}
