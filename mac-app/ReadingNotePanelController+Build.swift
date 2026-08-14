import Cocoa

extension ReadingNotePanelController {
    func buildContent(in panel: NSPanel) {
        rootView.wantsLayer = true
        rootView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = rootView

        configureAIToolbar()
        configureAskInput()
        aiActionButtons.forEach {
            configureAIButton($0)
            aiToolbar.addArrangedSubview($0)
        }
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        wordCountLabel.font = AppFont.semibold(ofSize: 12)
        wordCountLabel.alignment = .right
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = buildEditorScrollView()
        configureEditorTextView(in: scrollView)

        let titleStack = buildTitleStack()
        let topActions = buildTopActions()
        let metadata = buildMetadataStack()

        editorContainer.wantsLayer = true
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        let editorToolbar = buildEditorToolbar()
        editorContainer.addSubview(scrollView)
        editorContainer.addSubview(editorToolbar)
        editorContainer.addSubview(wordCountLabel)

        rootView.addSubview(titleStack)
        rootView.addSubview(topActions)
        rootView.addSubview(metadataView)
        rootView.addSubview(editorContainer)
        rootView.addSubview(statusLabel)
        rootView.addSubview(aiToolbarContainer)
        rootView.addSubview(askInputContainer)
        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            titleStack.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            topActions.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            topActions.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor),

            metadataView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 74),
            metadataView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.panelOuterMargin),
            metadataView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.panelOuterMargin),
            metadataView.heightAnchor.constraint(equalToConstant: Metrics.metadataHeight),
            metadata.stack.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor, constant: Metrics.metadataHorizontalInset),
            metadata.stack.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor, constant: -Metrics.metadataHorizontalInset),
            metadata.stack.centerYAnchor.constraint(equalTo: metadataView.centerYAnchor),
            metadata.bookItem.widthAnchor.constraint(lessThanOrEqualTo: metadata.stack.widthAnchor, multiplier: 0.3),

            editorContainer.topAnchor.constraint(equalTo: metadataView.bottomAnchor, constant: 10),
            editorContainer.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -42),

            scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editorToolbar.topAnchor),
            editorToolbar.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorToolbar.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorToolbar.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            editorToolbar.heightAnchor.constraint(equalToConstant: Metrics.editorToolbarHeight),
            statusLabel.leadingAnchor.constraint(equalTo: metadataView.leadingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: metadataView.trailingAnchor, constant: -6),
            statusLabel.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -9),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
            wordCountLabel.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -20),
            wordCountLabel.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            wordCountLabel.widthAnchor.constraint(equalToConstant: 52)
        ])
        updateWordCount()
        DispatchQueue.main.async { [weak self] in
            self?.textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func buildEditorScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        self.scrollView = scrollView
        return scrollView
    }

    private func buildTitleStack() -> NSStackView {
        let title = NSTextField(labelWithString: AppText.localized("阅读笔记", "Reading Note"))
        title.font = AppFont.semibold(ofSize: 19)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.image = NSImage(systemSymbolName: "pencil.and.list.clipboard", accessibilityDescription: nil)
        titleIconView.setAccessibilityElement(false)
        titleIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        titleIconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let stack = NSStackView(views: [titleIconView, title])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func buildTopActions() -> NSStackView {
        let listButton = iconButton(
            symbol: "sidebar.right",
            action: #selector(showNotesTapped(_:)),
            label: AppText.localized("阅读笔记列表", "Reading notes list"),
            pointSize: Metrics.topIconPointSize
        )
        let moreButton = iconButton(
            symbol: "ellipsis.curlybraces",
            action: #selector(moreTapped(_:)),
            label: AppText.localized("更多操作", "More actions"),
            pointSize: Metrics.topIconPointSize
        )
        topIconButtons = [listButton, moreButton]

        let stack = NSStackView(views: [listButton, moreButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func buildMetadataStack() -> (stack: NSStackView, bookItem: NSView) {
        metadataView.wantsLayer = true
        metadataView.translatesAutoresizingMaskIntoConstraints = false
        let bookMeta = metadataItem(title: AppText.localized("书籍", "Book"), value: note.documentTitle)
        let locationMeta = metadataItem(title: AppText.localized("位置", "Location"), value: noteLocationText())
        let createdMeta = metadataItem(title: AppText.localized("创建时间", "Created"), value: createdAtText())
        let stack = NSStackView(views: [bookMeta, locationMeta, createdMeta])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        metadataView.addSubview(stack)
        return (stack, bookMeta)
    }

    private func metadataItem(title: String, value: String) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = AppFont.semibold(ofSize: Metrics.metadataFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = AppFont.semibold(ofSize: Metrics.metadataFontSize)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func buildEditorToolbar() -> NSStackView {
        let save = iconButton(
            symbol: "square.and.arrow.down",
            action: #selector(saveTapped(_:)),
            label: AppText.localized("保存当前阅读笔记", "Save this reading note")
        )
        let undo = iconButton(
            symbol: "arrow.uturn.backward",
            action: #selector(undoTapped(_:)),
            label: AppText.localized("撤销", "Undo")
        )
        let redo = iconButton(
            symbol: "arrow.uturn.forward",
            action: #selector(redoTapped(_:)),
            label: AppText.localized("重做", "Redo")
        )
        let bold = textButton(title: "B", action: #selector(boldTapped(_:)))
        let italic = textButton(title: "I", action: #selector(italicTapped(_:)))
        italic.font = NSFontManager.shared.convert(AppFont.semibold(ofSize: 16), toHaveTrait: .italicFontMask)
        let list = iconButton(
            symbol: "list.bullet",
            action: #selector(listTapped(_:)),
            label: AppText.localized("项目符号列表", "Bulleted list")
        )
        let check = iconButton(
            symbol: "checklist",
            action: #selector(checklistTapped(_:)),
            label: AppText.localized("检查清单", "Checklist")
        )
        let template = iconButton(
            symbol: "doc.plaintext",
            action: #selector(templateTapped(_:)),
            label: AppText.localized("插入阅读笔记模板", "Insert reading note template")
        )
        let image = iconButton(
            symbol: "photo",
            action: #selector(imageTapped(_:)),
            label: AppText.localized("插入图片", "Insert image")
        )
        let buttons = [save, undo, redo, toolbarSeparator(), bold, italic, list, check, template, image]
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 86)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func toolbarSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func configureAIToolbar() {
        aiToolbarContainer.isHidden = true
        aiToolbarContainer.wantsLayer = true
        aiToolbarContainer.layer?.cornerRadius = 9
        aiToolbarContainer.layer?.shadowOpacity = 0.16
        aiToolbarContainer.layer?.shadowRadius = 12
        aiToolbarContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        aiToolbarContainer.frame = NSRect(x: 0, y: 0, width: 360, height: 38)

        aiToolbar.orientation = .horizontal
        aiToolbar.alignment = .centerY
        aiToolbar.distribution = .fillEqually
        aiToolbar.spacing = 4
        aiToolbar.edgeInsets = NSEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        aiToolbar.translatesAutoresizingMaskIntoConstraints = false
        aiToolbarContainer.addSubview(aiToolbar)
        NSLayoutConstraint.activate([
            aiToolbar.topAnchor.constraint(equalTo: aiToolbarContainer.topAnchor),
            aiToolbar.leadingAnchor.constraint(equalTo: aiToolbarContainer.leadingAnchor),
            aiToolbar.trailingAnchor.constraint(equalTo: aiToolbarContainer.trailingAnchor),
            aiToolbar.bottomAnchor.constraint(equalTo: aiToolbarContainer.bottomAnchor)
        ])
    }

    private func configureAskInput() {
        setAskInputVisible(false)
        askInputContainer.wantsLayer = true
        askInputContainer.layer?.cornerRadius = 9
        askInputContainer.layer?.shadowOpacity = 0.16
        askInputContainer.layer?.shadowRadius = 12
        askInputContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        askInputContainer.frame = NSRect(x: 0, y: 0, width: 340, height: 42)

        askInputField.placeholderString = AppText.localized("输入问题", "Ask about the selection")
        askInputField.font = NSFont.systemFont(ofSize: 14)
        askInputField.isBordered = false
        askInputField.drawsBackground = false
        askInputField.focusRingType = .none
        askInputField.target = self
        askInputField.action = #selector(submitAskQuestion(_:))
        askInputField.translatesAutoresizingMaskIntoConstraints = false

        askSendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        askSendButton.setAccessibilityLabel(AppText.send)
        askSendButton.isBordered = false
        askSendButton.target = self
        askSendButton.action = #selector(submitAskQuestion(_:))
        askSendButton.translatesAutoresizingMaskIntoConstraints = false

        askInputContainer.addSubview(askInputField)
        askInputContainer.addSubview(askSendButton)
        NSLayoutConstraint.activate([
            askInputField.leadingAnchor.constraint(equalTo: askInputContainer.leadingAnchor, constant: 12),
            askInputField.trailingAnchor.constraint(equalTo: askSendButton.leadingAnchor, constant: -8),
            askInputField.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.trailingAnchor.constraint(equalTo: askInputContainer.trailingAnchor, constant: -10),
            askSendButton.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.widthAnchor.constraint(equalToConstant: 26),
            askSendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func configureAIButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.font = AppFont.semibold(ofSize: 13)
        button.target = self
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 52).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        switch button {
        case explainButton:
            button.action = #selector(explainSelection(_:))
        case translateButton:
            button.action = #selector(translateSelection(_:))
        case summarizeButton:
            button.action = #selector(summarizeSelection(_:))
        case polishButton:
            button.action = #selector(polishSelection(_:))
        case difficultSentenceButton:
            button.action = #selector(analyzeDifficultSentence(_:))
        case askButton:
            button.action = #selector(showAskInput(_:))
        default:
            break
        }
    }

    private func iconButton(symbol: String, action: Selector, label: String, pointSize: CGFloat = 15) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        let button = ReadingNoteIconButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.setAccessibilityLabel(label)
        button.toolTip = label
        return button
    }

    private func textButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }
}
