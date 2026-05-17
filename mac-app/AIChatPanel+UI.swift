import Cocoa

extension AIChatPanel {
    func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor

        askButton.target = self
        askButton.action = #selector(startQuestion)
        askButton.isBordered = false
        askButton.isEnabled = false
        askButton.wantsLayer = true
        askButton.layer?.shadowColor = NSColor(red: 0.22, green: 0.32, blue: 0.92, alpha: 1).cgColor
        askButton.layer?.shadowOpacity = 0.24
        askButton.layer?.shadowRadius = 9
        askButton.layer?.shadowOffset = CGSize(width: 0, height: -3)
        askButton.translatesAutoresizingMaskIntoConstraints = false

        summaryButton.title = AppText.localized("总结", "Summarize")
        summaryButton.controlSize = .regular
        summaryButton.font = AppFont.semibold(ofSize: 13)
        summaryButton.isDark = isDarkMode
        summaryButton.target = self
        summaryButton.action = #selector(summarizeCurrentContent)
        summaryButton.translatesAutoresizingMaskIntoConstraints = false

        translateButton.title = AppText.localized("翻译", "Translate")
        translateButton.controlSize = .regular
        translateButton.font = AppFont.semibold(ofSize: 13)
        translateButton.isDark = isDarkMode
        translateButton.target = self
        translateButton.action = #selector(translateCurrentContent)
        translateButton.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        transcriptStack.orientation = .vertical
        transcriptStack.alignment = .leading
        transcriptStack.spacing = 10
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = transcriptStack

        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.textColor = NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingDots.isHidden = true
        loadingDots.translatesAutoresizingMaskIntoConstraints = false
        cancelRequestButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: AppText.cancel)
        cancelRequestButton.isBordered = false
        cancelRequestButton.contentTintColor = NSColor(red: 0.48, green: 0.50, blue: 0.56, alpha: 1)
        cancelRequestButton.target = self
        cancelRequestButton.action = #selector(cancelCurrentRequest)
        cancelRequestButton.isHidden = true
        cancelRequestButton.translatesAutoresizingMaskIntoConstraints = false

        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(loadingDots)
        statusRow.addSubview(statusLabel)
        statusRow.addSubview(cancelRequestButton)

        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).cgColor
        inputBar.layer?.cornerRadius = 8
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholderString = AppText.followUpPlaceholder
        inputField.font = NSFont.systemFont(ofSize: Self.readerBodyFontSize)
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(sendFollowUp)
        inputField.translatesAutoresizingMaskIntoConstraints = false

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendFollowUp)
        sendButton.contentTintColor = NSColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
        for view in [askButton, summaryButton, translateButton, scrollView, statusRow, inputBar] {
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            askButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            askButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            askButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            askButton.heightAnchor.constraint(equalToConstant: 44),

            summaryButton.topAnchor.constraint(equalTo: askButton.bottomAnchor, constant: 10),
            summaryButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            summaryButton.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -5),
            summaryButton.heightAnchor.constraint(equalToConstant: 32),

            translateButton.topAnchor.constraint(equalTo: summaryButton.topAnchor),
            translateButton.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 5),
            translateButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            translateButton.heightAnchor.constraint(equalTo: summaryButton.heightAnchor),

            scrollView.topAnchor.constraint(equalTo: summaryButton.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: statusRow.topAnchor, constant: -8),

            transcriptStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            transcriptStack.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            transcriptStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            statusRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusRow.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),
            statusRow.heightAnchor.constraint(equalToConstant: 18),

            loadingDots.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor),
            loadingDots.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            loadingDots.widthAnchor.constraint(equalToConstant: 22),
            loadingDots.heightAnchor.constraint(equalToConstant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: loadingDots.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelRequestButton.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            cancelRequestButton.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor),
            cancelRequestButton.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            cancelRequestButton.widthAnchor.constraint(equalToConstant: 22),
            cancelRequestButton.heightAnchor.constraint(equalToConstant: 22),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            inputBar.heightAnchor.constraint(equalToConstant: 44),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    func refreshLanguage() {
        inputField.placeholderString = AppText.followUpPlaceholder
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        summaryButton.title = AppText.localized("总结", "Summarize")
        translateButton.title = AppText.localized("翻译", "Translate")
        summaryButton.needsDisplay = true
        translateButton.needsDisplay = true
        askButton.needsDisplay = true
        if !messages.isEmpty, messages[0].role == "system" {
            messages[0] = ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        }
    }
}

